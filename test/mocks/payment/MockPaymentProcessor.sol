// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/PaymentProcessor.sol";

abstract contract MockPaymentProcessor is PaymentProcessor {
    uint256 public balance = 0;

    constructor() {}

    function _deposit(address from, uint256 paymentWad) internal override {
        balance += paymentWad;
    }

    function _withdraw(address to, uint256 paymentWad) internal override {
        balance -= paymentWad;
    }

    function _balance() internal view override returns (uint256) {
        return balance;
    }

    function setBalance(uint256 balanceWad) external {
        balance = balanceWad;
    }
}