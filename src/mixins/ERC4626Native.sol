// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { AbstractERC4626 } from "src/mixins/AbstractERC4626.sol";

abstract contract ERC4626Native is ERC20, AbstractERC4626 {
    using FixedPointMathLib for uint256;

    constructor(
        string memory _name,
        string memory _symbol
    ) AbstractERC4626(_name, _symbol, 18) {}

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public payable virtual returns (uint256 shares) {
        require(msg.value == assets, "INVALID_ETH_AMOUNT");
        // Check for rounding error since we round down in previewDeposit.
        require((shares = convertToSharesInternal(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public payable virtual returns (uint256 assets) {
        assets = previewMintInternal(shares, msg.value); // No need to check for rounding error, previewMint rounds up.
        require(msg.value == assets, "INVALID_ETH_AMOUNT");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(receiver, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // To be used internally by Deposit, since depositing eth immediately credits it to the account
    function convertToSharesInternal(uint256 assets) internal view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        // Using assets here is fine as we explicitly require msg.value == assets in deposit()
        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets() - assets);
    }

    // To be used internally by Mint, since depositing eth immediately credits it to the account
    function previewMintInternal(uint256 shares, uint256 depositAmount) internal virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets() - depositAmount, supply);
    }

    function _transfer(address recipient, uint256 assets) internal virtual override {
        SafeTransferLib.safeTransferETH(recipient, assets);
    }
}