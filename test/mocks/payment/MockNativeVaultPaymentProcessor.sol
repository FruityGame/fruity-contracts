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

    constructor(VaultParams memory params)
        NativeVaultPaymentProcessor(params)
    {}

    function depositExternal(address from, uint256 paymentWad) external payable {
        _deposit(from, paymentWad);
    }

    function withdrawExternal(address to, uint256 paymentWad) external {
        _withdraw(to, paymentWad);
    }

    /*
        ERC4626 Hooks
    */
    function afterBurn(address owner, address receiver, uint256 shares) internal override {}
    function afterDeposit(address owner, uint256 assets, uint256 shares) internal override {}
}