// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/vault/ERC20VaultPaymentProcessor.sol";

contract MockERC20PaymentProcessor is ERC20VaultPaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance()) {
            revert InsufficientFunds(address(this), _balance(), payoutWad);
        }
        _;
    }

    constructor(address asset, string memory name, string memory symbol)
        ERC20VaultPaymentProcessor(asset, name, symbol)
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