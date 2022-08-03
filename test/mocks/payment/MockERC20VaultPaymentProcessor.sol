// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/vault/ERC20VaultPaymentProcessor.sol";

uint256 constant JACKPOT_RESERVATION = 20 * 1e18;

contract MockERC20PaymentProcessor is ERC20VaultPaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance() - JACKPOT_RESERVATION) {
            revert InsufficientFunds(address(this), _balance() - JACKPOT_RESERVATION, payoutWad);
        }
        _;
    }

    constructor(VaultParams memory params) ERC20VaultPaymentProcessor(params) {}

    function totalAssets() public view override returns (uint256) {
        return _balance() - JACKPOT_RESERVATION;
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