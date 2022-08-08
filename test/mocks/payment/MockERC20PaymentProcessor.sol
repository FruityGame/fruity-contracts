// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import "src/payment/ERC20PaymentProcessor.sol";
import "src/payment/PaymentProcessor.sol";

uint256 constant JACKPOT_RESERVATION = 20 * 1e18;

contract MockERC20PaymentProcessor is ERC20PaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        if (payoutWad > _balance() - JACKPOT_RESERVATION) {
            revert InsufficientFunds(address(this), _balance() - JACKPOT_RESERVATION, payoutWad);
        }
        _;
    }

    constructor(ERC20 token) ERC20PaymentProcessor(token) {}

    function depositExternal(address from, uint256 paymentWad) external payable {
        _deposit(from, paymentWad);
    }

    function withdrawExternal(address to, uint256 paymentWad) external {
        _withdraw(to, paymentWad);
    }
}