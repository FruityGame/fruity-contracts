// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/payment/PaymentProcessor.sol";

abstract contract MockPaymentProcessor is PaymentProcessor {
    uint256 public balance = 0;

    function _deposit(address, uint256 paymentWad) internal override {
        balance += paymentWad;
    }

    function _withdraw(address, uint256 paymentWad) internal override {
        balance -= paymentWad;
    }

    function _balance() public view override returns (uint256) {
        return balance;
    }

    function setBalance(uint256 balanceWad) external {
        balance = balanceWad;
    }
}