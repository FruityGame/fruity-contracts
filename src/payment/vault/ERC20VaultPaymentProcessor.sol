// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "src/mixins/ERC4626.sol";
import { ERC20PaymentProcessor } from "src/payment/ERC20PaymentProcessor.sol";

abstract contract ERC20VaultPaymentProcessor is ERC20PaymentProcessor, ERC4626 {
    struct VaultParams {
        ERC20 asset;
        string name;
        string symbol;
    }

    constructor(VaultParams memory params)
        ERC20PaymentProcessor(params.asset)
        ERC4626(params.asset, params.name, params.symbol)
    {}

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual override canAfford(assets) {}
    function totalAssets() public view override returns (uint256) {
        return _balance();
    }
}