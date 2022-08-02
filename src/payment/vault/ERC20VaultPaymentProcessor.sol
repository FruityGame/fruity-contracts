// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/ERC20PaymentProcessor.sol";
import "src/payment/vault/VaultPaymentProcessor.sol";

abstract contract ERC20VaultPaymentProcessor is VaultPaymentProcessor, ERC20PaymentProcessor {
    constructor(VaultParams memory params) ERC20PaymentProcessor(params.asset) VaultPaymentProcessor(params) {}
}