// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { WETH } from "solmate/tokens/WETH.sol";

import "src/payment/NativePaymentProcessor.sol";
import "src/payment/vault/VaultPaymentProcessor.sol";
import "src/payment/PaymentProcessor.sol";

abstract contract NativeVaultPaymentProcessor is VaultPaymentProcessor, NativePaymentProcessor {
    WETH public native;

    modifier preDepositHook(uint256 paymentWad) override {
        native.deposit{value: msg.value}();
        _;
    }

    modifier preWithdrawHook(uint256 paymentWad) override {
        native.withdraw(paymentWad);
        _;
    }

    constructor(VaultParams memory params) VaultPaymentProcessor(params) {
        native = WETH(payable(params.asset));
    }

    function __balance() internal view override returns (uint256) {
        return native.balanceOf(address(this));
    }
}