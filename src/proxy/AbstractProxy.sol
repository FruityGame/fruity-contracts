// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ECDSA } from "src/libraries/crypto/ECDSA.sol";
import { EIP712 } from "src/mixins/EIP712.sol";

abstract contract AbstractProxy is EIP712 {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public SESSION_TYPEHASH = keccak256("SessionCertificate(address user,address proxy,uint256 expiry,uint256 nonce)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            ERRORS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    error InvalidSession(address user);
    error InvalidSignature(address expected);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        INTERNAL METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function _validateMessage(
        address expected,
        bytes32 hashedMessage,
        bytes32 domainSeperator,
        uint8 v, bytes32 r, bytes32 s
    ) internal pure {
        // EIP712, Recover message signed with the Proxy key
        address recoveredAddress = ecrecover(
            hashTypedData(hashedMessage, domainSeperator), v, r, s
        );

        if (recoveredAddress != expected || recoveredAddress == address(0)) revert InvalidSignature(expected);
    }

    function _validateMessage(
        address expected,
        bytes32 hashedMessage,
        bytes32 domainSeperator,
        bytes32 r,
        bytes32 vs
    ) internal pure {
        (uint8 v,,bytes32 s) = ECDSA.expand(r, vs);
        return _validateMessage(expected, hashedMessage, domainSeperator, v, r, s);
    }
}