// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/payment/NativePaymentProcessor.sol";
import "src/payment/PaymentProcessor.sol";

uint256 constant JACKPOT_RESERVATION = 20 * 1e18;

contract MockNativePaymentProcessor is NativePaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance() - JACKPOT_RESERVATION) {
            revert InsufficientFunds(address(this), _balance() - JACKPOT_RESERVATION, payoutWad);
        }
        _;
    }

    function depositExternal(address from, uint256 paymentWad) external payable {
        _deposit(from, paymentWad);
    }

    function withdrawExternal(address to, uint256 paymentWad) external {
        _withdraw(to, paymentWad);
    }
}