
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { ERC20Hooks } from "src/tokens/ERC20Hooks.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";

abstract contract ERC20Snapshot is ERC20Hooks {
    using Checkpoints for Checkpoints.History;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    Checkpoints.History internal totalSupplyCheckpoints;
    mapping(address => Checkpoints.History) internal balanceCheckpoints;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                         PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function getTotalSupplyAt(uint256 blockNumber) public view virtual returns (uint256) {
        return totalSupplyCheckpoints.getAtBlock(blockNumber);
    }

    function getBalanceAt(address user, uint256 blockNumber) public view virtual returns (uint256) {
        return balanceCheckpoints[user].getAtBlock(blockNumber);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                         INTERNAL HOOKS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function _afterMint(address to, uint256 newBalance, uint256 newTotalSupply) internal virtual override {
        if (to != address(this)) balanceCheckpoints[to].push(newBalance);
        totalSupplyCheckpoints.push(newTotalSupply);
    }

    function _afterBurn(address from, uint256 newBalance, uint256 newTotalSupply) internal virtual override {
        // Only update the shares for user `from` if they're not us (i.e. an internal burn)
        if (from != address(this)) balanceCheckpoints[from].push(newBalance);
        totalSupplyCheckpoints.push(newTotalSupply);
    }

    function _afterTransfer(address from, address to, uint256 fromNewBalance, uint256 toNewBalance) internal virtual override {
        if (from != address(this)) balanceCheckpoints[from].push(fromNewBalance);
        if (to != address(this)) balanceCheckpoints[to].push(toNewBalance);
    }
}
