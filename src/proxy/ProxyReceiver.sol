// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ECDSA } from "src/libraries/crypto/ECDSA.sol";
import { EIP712 } from "src/mixins/EIP712.sol";
import { Certificates } from "src/libraries/crypto/Certificates.sol";

import { AbstractProxy } from "src/proxy/AbstractProxy.sol";
import { ProxyRelayer } from "src/proxy/ProxyRelayer.sol";

abstract contract ProxyReceiver is AbstractProxy {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public EXECUTE_PROXY_TYPEHASH = keccak256("ExecuteProxy(address target,bytes _calldata,uint256 nonce)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    mapping(address => uint256) public userNonces;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    event ProxyRequestComplete(address indexed user, bool succeeded);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    constructor() EIP712(string(abi.encodePacked(address(this), "ProxyReceiver")), "1") {}

    function executeProxy(
        bytes32 rCert,
        bytes32 vsCert,
        uint256 certLhs,
        uint256 certRhs,
        bytes32 r,
        bytes32 vs,
        bytes calldata _calldata
    ) public returns (bool success) {
        // Decompress/Unpack the certificate contents
        (address user, address proxy, uint256 expiry) = Certificates.expand(certLhs, certRhs);

        // Invalid or Expired Certificate
        if (user == address(0) || proxy == address(0) || block.number > expiry) {
            revert InvalidSession(user);
        }

        // Validate the user's Session from the Sender
        _validateMessage(
            user,
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    user,
                    proxy,
                    expiry,
                    ProxyRelayer(msg.sender).sessionNonces(user)
                )
            ),
            EIP712(msg.sender).DOMAIN_SEPARATOR(),
            rCert, vsCert
        );

        // Validate the message signed with the Proxy Key, and is for this Relayer
        _validateMessage(
            proxy,
            keccak256(
                abi.encode(
                    EXECUTE_PROXY_TYPEHASH,
                    address(this),
                    _calldata,
                    userNonces[user]++
                )
            ),
            DOMAIN_SEPARATOR(),
            r, vs
        );

        // Call our function. Beyond this point, the relayer has performed correctly,
        // therefore they can keep the fee. If the function call fails, it's PEBKAC
        (success, ) = address(this).call(_calldata);

        emit ProxyRequestComplete(user, success);
    }
}