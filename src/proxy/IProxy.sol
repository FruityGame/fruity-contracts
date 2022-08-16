// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ECDSA } from "src/libraries/ECDSA.sol";
import { EIP712 } from "src/mixins/EIP712.sol";

abstract contract IProxy is EIP712 {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public SESSION_TYPEHASH = keccak256("SessionCertificate(address user,address proxy,uint256 expiry)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            ERRORS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    error InvalidSession(address user);
    error InvalidSignature(address proxy);
    error InvalidRelayer(address relayer);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function getSessionKey(address user, address proxy, uint256 expiry) public view returns(bytes32) {
        return bytes32(keccak256(abi.encodePacked(user, proxy, expiry)));
    }

    function getNonceKey(address user, address proxy) public view returns(bytes32) {
        return bytes32(keccak256(abi.encodePacked(msg.sender, user, proxy)));
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        INTERNAL METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function _validateMessage(
        address expected,
        bytes32 hashedMessage,
        bytes32 domainSeperator,
        uint8 v, bytes32 r, bytes32 s
    ) internal view {
        // EIP712, Recover message signed with the Proxy key
        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    domainSeperator,
                    hashedMessage
                )
            ), v, r, s
        );

        if (recoveredAddress != expected || recoveredAddress == address(0)) revert InvalidSignature(recoveredAddress);
    }

    function _validateMessage(
        address expected,
        bytes32 hashedMessage,
        bytes32 domainSeperator,
        bytes32 r,
        bytes32 vs
    ) internal view {
        (uint8 v,,bytes32 s) = ECDSA.expand(r, vs);
        return _validateMessage(expected, hashedMessage, domainSeperator, v, r, s);
    }
}