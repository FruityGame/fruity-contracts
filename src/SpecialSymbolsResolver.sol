// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

abstract contract SpecialSymbolsResolver {
    function resolveSpecialSymbols(uint256 symbol, uint256 count, uint256 rowSize) external virtual;
}