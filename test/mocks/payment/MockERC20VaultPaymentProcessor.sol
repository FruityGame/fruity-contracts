// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import "src/payment/vault/ERC20VaultPaymentProcessor.sol";

contract MockERC20VaultPaymentProcessor is ERC20VaultPaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance()) {
            revert InsufficientFunds(address(this), _balance(), payoutWad);
        }
        _;
    }

    constructor(VaultParams memory params)
        ERC20VaultPaymentProcessor(params)
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