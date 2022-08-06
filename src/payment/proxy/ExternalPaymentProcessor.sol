// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/auth/Auth.sol";
import "src/payment/PaymentProcessor.sol";

abstract contract ExternalPaymentProcessor is PaymentProcessor, Auth {
    function depositExternal(address from, uint256 paymentWad) external virtual requiresAuth() {
        _deposit(from, paymentWad);
    }

    function withdrawExternal(address to, uint256 paymentWad) external virtual requiresAuth() {
        _withdraw(to, paymentWad);
    }
}