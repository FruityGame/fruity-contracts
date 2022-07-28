// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/SpecialSymbolsResolver.sol";

contract MockSpecialSymbolsResolver is SpecialSymbolsResolver {
    function resolveSpecialSymbols(uint256 symbol, uint256 count, uint256 rowSize) external pure override {
        return;
    }
}