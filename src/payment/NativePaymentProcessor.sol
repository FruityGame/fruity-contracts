// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/PaymentProcessor.sol";

abstract contract NativePaymentProcessor is PaymentProcessor {

    error PaymentError(address user, uint256 payoutWad);

    modifier preDepositHook() virtual {
        _;
    }

    modifier preWithdrawHook(uint256 paymentWad) virtual {
        _;
    }

    modifier userCanAfford(uint256 betWad) {
        if (msg.value != betWad) revert InsufficientFunds(msg.sender, msg.value, betWad);
        _;
    }

    function _deposit(address from, uint256 paymentWad) internal override userCanAfford(paymentWad) preDepositHook() {}

    function _withdraw(address to, uint256 paymentWad) internal override canAfford(paymentWad) preWithdrawHook(paymentWad) {
        (bool success, ) = payable(to).call{value: paymentWad}("");
        if (!success) revert PaymentError(to, paymentWad);
    }

    function _balance() internal view override returns (uint256) {
        return __balance();
    }

    function __balance() internal view virtual returns (uint256) {
        return address(this).balance;
    }
}