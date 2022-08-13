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
        ERC20 Hooks
    */

    function _afterMint(address to, uint256 newBalance, uint256 newTotalSupply) internal virtual override {}

    function _afterBurn(address from, uint256 newBalance, uint256 newTotalSupply) internal virtual override {}

    function _afterTransfer(address from, address to, uint256 fromNewBalance, uint256 toNewBalance) internal virtual override {}
}