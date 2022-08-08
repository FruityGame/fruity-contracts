// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "src/mixins/ERC4626.sol";
import { ERC20PaymentProcessor } from "src/payment/ERC20PaymentProcessor.sol";

abstract contract ERC20VaultPaymentProcessor is ERC20PaymentProcessor, ERC4626 {
    constructor(address asset, string memory name, string memory symbol)
        ERC20PaymentProcessor(asset)
        ERC4626(ERC20(asset), name, symbol)
    {}

    function beforeWithdraw(uint256 assets, uint256 shares) internal override canAfford(assets) {}
    function totalAssets() public view override returns (uint256) {
        return _balance();
    }
}