// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { ERC4626Native } from "src/mixins/ERC4626Native.sol";
import { NativePaymentProcessor } from "src/payment/NativePaymentProcessor.sol";

abstract contract NativeVaultPaymentProcessor is NativePaymentProcessor, ERC4626Native {
    constructor(string memory name, string memory symbol) ERC4626Native(name, symbol) {}

    function beforeWithdraw(uint256 assets, uint256 shares) internal override canAfford(assets) {}
    function totalAssets() public view override returns (uint256) {
        return _balance();
    }
}