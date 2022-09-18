// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ECDSA } from "src/libraries/crypto/ECDSA.sol";
import { EIP712 } from "src/mixins/EIP712.sol";
import { Certificates } from "src/libraries/crypto/Certificates.sol";
import { ProxyReceiver } from "src/proxy/ProxyReceiver.sol";

import "forge-std/Test.sol";

abstract contract ProxyTest is EIP712, Test {
    // I hate this language so much, why can't I reference a const
    // from a yet to be compiled/deployed contract? It's rarted
    bytes32 constant public SESSION_TYPEHASH = keccak256("SessionCertificate(address user,address proxy,uint256 expiry,uint256 nonce)");
    bytes32 constant public EXECUTE_PROXY_TYPEHASH = keccak256("ExecuteProxy(address target,bytes _calldata,uint256 nonce)");
    bytes32 constant public END_SESSION_TYPEHASH = keccak256("EndSession(address user,address proxy,uint256 expiry,uint256 nonce)");

    function signAndCompress(
        uint256 key,
        bytes32 messageHash
    ) internal returns (bytes32 _r, bytes32 _vs) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, messageHash);
        (_r, _vs) = ECDSA.compress(v, r, s);
    }

    function createSignedExecuteProxyMessage(
        address target,
        bytes memory _calldata,
        uint256 nonce,
        uint256 key,
        bytes32 domainSeparator
    ) internal returns (bytes32, bytes32) {
        bytes memory message = abi.encode(
            EXECUTE_PROXY_TYPEHASH,
            target,
            _calldata,
            nonce
        );

        return signAndCompress(
            key,
            hashTypedData(keccak256(message), domainSeparator)
        );
    }

    function createSignedSessionMessage(
        address user,
        address proxy,
        uint192 expiry,
        uint256 nonce,
        uint256 key,
        bytes32 domainSeparator
    ) internal returns (bytes32, bytes32) {
        bytes memory message = abi.encode(
            SESSION_TYPEHASH,
            user,
            proxy,
            expiry,
            nonce
        );

        return signAndCompress(
            key,
            hashTypedData(keccak256(message), domainSeparator)
        );
    }

    // Yes yes, code duplication. I know, I could pass the typeHash as
    // an arg, but I felt like it was beggining to become too large/too much
    function createSignedEndSessionMessage(
        address user,
        address proxy,
        uint192 expiry,
        uint256 nonce,
        uint256 key,
        bytes32 domainSeparator
    ) internal returns (bytes32, bytes32) {
        bytes memory message = abi.encode(
            END_SESSION_TYPEHASH,
            user,
            proxy,
            expiry,
            nonce
        );

        return signAndCompress(
            key,
            hashTypedData(keccak256(message), domainSeparator)
        );
    }

    function createSessionCertificate(
        address user,
        address proxy,
        uint192 expiry,
        uint256 nonce,
        uint256 key,
        bytes32 domainSeparator
    ) internal returns (bytes32, bytes32, uint256, uint256) {
        // Setup a session message
        (bytes32 rCert, bytes32 vsCert) = createSignedSessionMessage(
            user,
            proxy,
            expiry,
            nonce,
            key,
            domainSeparator
        );

        // Compress the Session Certificate
        (uint256 certLhs, uint256 certRhs) = Certificates.compress(user, proxy, expiry);

        return (rCert, vsCert, certLhs, certRhs);
    }
}