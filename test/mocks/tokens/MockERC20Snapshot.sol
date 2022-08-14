// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Checkpoints } from "src/libraries/Checkpoints.sol";

import { ERC20Hooks } from "src/tokens/ERC20Hooks.sol";
import { ERC20Snapshot } from "src/tokens/ERC20Snapshot.sol";

contract MockERC20Snapshot is ERC20Snapshot {
    using Checkpoints for Checkpoints.History;

    constructor(uint256 quantityWad) ERC20Hooks("FRUITY", "FRTY", 18) {
        _mint(msg.sender, quantityWad);
    }

    function mintExternal(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burnExternal(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function pushTotalSupplyCheckpoint(uint256 _totalSupply) external {
        totalSupplyCheckpoints.push(_totalSupply);
    }
}