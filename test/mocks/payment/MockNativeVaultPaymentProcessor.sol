// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/vault/NativeVaultPaymentProcessor.sol";

contract MockNativeVaultPaymentProcessor is NativeVaultPaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance()) {
            revert InsufficientFunds(address(this), _balance(), payoutWad);
        }
        _;
    }

    constructor(string memory name, string memory symbol)
        NativeVaultPaymentProcessor(name, symbol)
    {}

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