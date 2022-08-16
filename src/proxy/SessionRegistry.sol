// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { EIP712 } from "src/mixins/EIP712.sol";
import { Certificates } from "src/libraries/Certificates.sol";

import { IProxy } from "src/proxy/IProxy.sol";
import { ProxyReceiver } from "src/proxy/ProxyReceiver.sol";

contract SessionRegistry is IProxy {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public END_SESSION_TYPEHASH = keccak256("EndSession(address user,address proxy,uint256 expiry)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    uint256 public fee;
    uint256 public minimumStake;

    mapping(bytes32 => bool) public sessions;
    mapping(address => bool) public relayers;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    event SessionRegistered(address indexed user, address proxy, uint256 expiry);
    event SessionUnregistered(address indexed user, address proxy);

    error InvalidProxyAddress(address proxy);
    error InvalidExpiry(uint256 expiry);

    constructor(uint256 _fee) EIP712(string(abi.encodePacked(address(this), "SessionRegistry")), "1") {
        fee = _fee;
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function registerSession(address proxy, uint192 expiry, bytes32 r, bytes32 vs) public {
        if (proxy == address(0)) revert InvalidProxyAddress(proxy);
        if (expiry < block.number) revert InvalidExpiry(expiry);

        // Validate the user's Session Certificate before cataloguing it
        _validateMessage(
            msg.sender,
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    msg.sender,
                    proxy,
                    expiry
                )
            ),
            DOMAIN_SEPARATOR(),
            r, vs
        );

        sessions[getSessionKey(msg.sender, proxy, expiry)] = true;

        emit SessionRegistered(msg.sender, proxy, expiry);
    }

    function unregisterSession(
        bytes32 rCert,
        bytes32 vsCert,
        uint256 certLhs,
        uint256 certRhs,
        bytes32 r,
        bytes32 vs
    ) public {
        // Decompress/Unpack the certificate contents
        (address user, address proxy, uint256 expiry) = Certificates.expand(certLhs, certRhs);
        if (user == address(0) || proxy == address(0)) revert InvalidSession(user);

        // Validate the user's Session Certificate before cataloguing it
        _validateMessage(
            user,
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    user,
                    proxy,
                    expiry
                )
            ),
            DOMAIN_SEPARATOR(),
            rCert, vsCert
        );

        // Validate the Proxy End Session request
        _validateMessage(
            proxy,
            keccak256(
                abi.encode(
                    END_SESSION_TYPEHASH,
                    user,
                    proxy,
                    expiry
                )
            ),
            DOMAIN_SEPARATOR(),
            r, vs
        );

        // Set their Session Validity to False
        delete sessions[getSessionKey(user, proxy, expiry)];

        emit SessionUnregistered(user, proxy);
    }

    function isRelayer(address relayer) external view returns (bool) {
        return relayers[relayer];
    }
}