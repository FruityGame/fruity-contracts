// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { EIP712 } from "src/mixins/EIP712.sol";
import { Certificates } from "src/libraries/Certificates.sol";

import { IProxy } from "src/proxy/IProxy.sol";
import { SessionRegistry } from "src/proxy/SessionRegistry.sol";
import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";

abstract contract ProxyReceiver is PaymentProcessor, IProxy {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public EXECUTE_PROXY_TYPEHASH = keccak256("ExecuteProxy(address target,bytes _calldata,uint256 nonce)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    mapping(bytes32 => uint256) public userNonces;
    mapping(bytes32 => uint256) public claims;

    SessionRegistry sessionRegistry;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    event ProxyRequestComplete(address indexed user, bool succeeded);
    event ProxyFeeClaimed(address indexed relayer, address indexed user, address proxy);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            MODIFIERS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    modifier canAfford(uint256 payment) virtual override {_;}

    constructor(SessionRegistry _sessionRegistry)
        EIP712(string(abi.encodePacked(address(this), "ProxyReceiver")), "1")
    {
        sessionRegistry = _sessionRegistry;
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function executeProxy(
        bytes32 rCert,
        bytes32 vsCert,
        uint256 certLhs,
        uint256 certRhs,
        bytes32 r,
        bytes32 vs,
        bytes calldata _calldata
    ) public returns (bool success) {
        // Ensure only registered Relayers can call this method
        if (!sessionRegistry.isRelayer(msg.sender)) {
            revert InvalidRelayer(msg.sender);
        }

        // Decompress/Unpack the certificate contents
        (address user, address proxy, uint256 expiry) = Certificates.expand(certLhs, certRhs);

        // (note): Written like this save bytecode. Ironically enough, this comment probably gets compiled in.
        if (
            user == address(0) || proxy == address(0) || // Invalid Certificate
            !sessionRegistry.sessions(getSessionKey(user, proxy, expiry)) || // Invalid Session (cancelled early)
            block.number > expiry // Expired Certificate
        ) {
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
                    expiry
                )
            ),
            sessionRegistry.DOMAIN_SEPARATOR(),
            rCert, vsCert
        );

        // Deposit the relayer fee, will do balance and allowance checks
        _deposit(user, sessionRegistry.fee());

        // Validate the message signed with the Proxy Key
        _validateMessage(
            proxy,
            keccak256(
                abi.encode(
                    EXECUTE_PROXY_TYPEHASH,
                    address(this),
                    _calldata,
                    userNonces[getNonceKey(user, proxy)]++
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

    function claimFee(address user, address proxy) public {
        // Get the Nonce Key associated with the sender/claimer
        bytes32 nonceKey = getNonceKey(user, proxy);
        // Calculate the number of requests they've fulfilled for the user since their last claim
        uint256 payment = (userNonces[nonceKey] - claims[nonceKey]) * 1e18;
        // Update the user's claims
        claims[nonceKey] = userNonces[nonceKey];

        _withdraw(msg.sender, payment);

        emit ProxyFeeClaimed(msg.sender, user, proxy);
    }
}