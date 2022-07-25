// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

library Board {
    uint256 constant MASK_4 = (0x1 << 4) - 1;

    modifier rowInBounds(uint256 row) {
        require(row < 3, "Row provided for query is out of bounds");
        _;
    }

    modifier indexInBounds(uint256 index) {
        require(index < 5, "Index provided for query is out of bounds");
        _;
    }

    function numToSymbol(uint256 result) public pure returns (uint256) {
        if (result <= 33) return 0;
        if (result <= 55) return 1;
        if (result <= 68) return 2;
        if (result <= 81) return 3;
        if (result <= 89) return 4;
        if (result <= 97) return 5;
        return 6;
    }

    function generate(uint256 entropy) external pure returns (uint256 out) {
        out = numToSymbol(entropy % 101);
        for (uint256 i = 0; i < 14; i++) {
            out = (out << 4) | numToSymbol((entropy >> i * 16) % 101);
        }
    }

    function get(uint256 board, uint256 row, uint256 index) internal pure
        rowInBounds(row)
        indexInBounds(index)
        returns (uint256)
    {
        return (board >> 20 * row + 4 * index) & MASK_4;
    }
}