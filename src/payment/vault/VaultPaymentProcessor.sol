// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/mixins/ERC4626.sol";
import "src/payment/PaymentProcessor.sol";

struct VaultParams {
    address asset;
    string name;
    string symbol;
}

abstract contract VaultPaymentProcessor is PaymentProcessor, ERC4626 {
    constructor(VaultParams memory params) ERC4626(ERC20(params.asset), params.name, params.symbol) {}

    function beforeWithdraw(uint256 assets, uint256 shares) internal override canAfford(assets) {}
}