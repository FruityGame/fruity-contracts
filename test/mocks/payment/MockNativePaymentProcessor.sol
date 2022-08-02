// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/NativePaymentProcessor.sol";
import "src/payment/PaymentProcessor.sol";

contract MockNativePaymentProcessor is NativePaymentProcessor {
    uint256 public preDepositCalls;
    uint256 public preWithdrawCalls;

    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance() - (20 * 1e18)) {
            revert InsufficientFunds(address(this), _balance() - (20 * 1e18), payoutWad);
        }
        _;
    }

    modifier preDepositHook() override {
        preDepositCalls++;
        _;
    }

    modifier preWithdrawHook(uint256 paymentWad) override {
        preWithdrawCalls++;
        _;
    }

    function depositExternal(address from, uint256 paymentWad) external payable {
        _deposit(from, paymentWad);
    }

    function withdrawExternal(address to, uint256 paymentWad) external {
        _withdraw(to, paymentWad);
    }

    function balanceExternal() external view returns (uint256) {
        return _balance();
    }
}