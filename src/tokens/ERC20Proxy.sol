
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { ERC20Hooks } from "src/tokens/ERC20Hooks.sol";

abstract contract ERC20Proxy is ERC20Hooks {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                          CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public TRANSFER_PROXY_TYPEHASH = keccak256("TransferProxy(address owner,address to,uint256 amount,address proxy,uint256 nonce)");
    bytes32 constant public END_SESSION_TYPEHASH = keccak256("EndSession(address owner,address proxy,uint256 nonce)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        DATA STRUCTURES
    /////////////////////////////////////////////////////////////////////////////////////////*/

    struct Session {
        address proxy;
        uint64 expiryBlock; // Block #
        uint32 sessionLength; // # of Blocks
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    event SessionCreated(address indexed owner);
    event SessionRefreshed(address indexed owner);
    event SessionEnded(address indexed owner);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    mapping(address => Session) internal sessions;
    mapping(address => uint256) public proxyNonces;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    // uint16 gives a max sessionLength of 65535 blocks, which should be ample for short-lived proxy sessions
    function createSession(address proxy, uint16 sessionLength) public virtual {
        require(proxy != address(0), "Invalid Proxy Address provided");

        // This will overwrite the user's session if one is already active. This is fine,
        // as it allows a user to refresh/change their session parameters
        sessions[msg.sender] = Session(
            proxy,
            uint64(block.number + sessionLength), // Safe because there'll never be 2^64 blocks produced in our lifetimes
            uint32(sessionLength) // Safe because sessionLength is uint16
        );

        emit SessionCreated(msg.sender);
    }

    function endSession() public virtual {
        _endSession(msg.sender);
    }

    function endSessionProxy(address owner, uint8 v, bytes32 r, bytes32 s) public virtual {
        // Get the Proxy Key for the owner's session
        address proxy = sessions[owner].proxy;

        // EIP712, Validate message signed with the Proxy key
        _validateProxyMessage(
            proxy,
            keccak256(abi.encode(END_SESSION_TYPEHASH, owner, proxy, proxyNonces[proxy]++)),
            v, r, s
        );

        // End the session
        _endSession(owner);
    }

    function transferProxy(
        address owner,
        address to,
        uint256 amount,
        uint8 v, bytes32 r, bytes32 s
    ) public virtual returns (bool) {
        // Get the session for the owner
        Session storage session = sessions[owner];
        // This will revert() if a session is uninitialized (ala is 0) as well
        require(block.number < session.expiryBlock, "Proxy Session does not exist");

        // Get the owner's delegated Proxy Address
        // (note): It's not possible to have the proxy address set to address(0),
        // as per the checks in createSession()
        address proxy = session.proxy;

        // EIP712, Validate message signed with the Proxy Key
        _validateProxyMessage(
            proxy,
            keccak256(abi.encode(TRANSFER_PROXY_TYPEHASH, owner, to, amount, proxy, proxyNonces[proxy]++)),
            v, r, s
        );

        // Refresh the session expiry
        // Safe because there'll never be 2^64 blocks produced in our lifetimes
        session.expiryBlock = uint64(block.number + session.sessionLength);

        emit SessionRefreshed(owner);

        // Okay to call as permissions are checked above
        return _transferFromUnchecked(owner, to, amount);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        INTERNAL METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function _validateProxyMessage(address proxy, bytes32 hashedMessage, uint8 v, bytes32 r, bytes32 s) internal view {
        // EIP712, Recover message signed with the Proxy key
        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    hashedMessage
                )
            ),
            v,
            r,
            s
        );

        require(recoveredAddress != address(0) && recoveredAddress == proxy, "Invalid Proxy Signature");
    }

    function _endSession(address user) internal virtual {
        // Zero'ing out the expiryBlock means transferProxy will always fail,
        // as it requires `block.number < session.expiryBlock`,
        // effectively cancelling the session
        require(sessions[user].expiryBlock != 0, "Proxy Session does not exist");
        sessions[user].expiryBlock = 0;

        emit SessionEnded(user);
    }
}
