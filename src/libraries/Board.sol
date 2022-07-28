// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/utils/FixedPointMathLib.sol";

uint256 constant WAD = 1e18;

library Board {
    uint256 constant MASK_4 = (0x1 << 4) - 1;

    modifier sizeWithinBounds(uint256 boardSize) {
        require(boardSize > 0 && boardSize <= 64, "Invalid board size provided");
        _;
    }

    modifier symbolsWithinBounds(uint256 symbolCount) {
        require(symbolCount > 0 && symbolCount <= 15, "Invalid number of symbols provided");
        _;
    }

    modifier payoutConstantWithinBounds(uint256 payoutConstant) {
        require(payoutConstant > 0, "Invalid payout constant provided");
        _;
    }

    function divideWads(uint256 lhs, uint256 rhs) internal pure returns (uint256) {
        return (lhs * WAD) / rhs;
    }

    function toWad(uint256 num) internal pure returns (uint256) {
        return num * WAD;
    }

    function entropyToSymbol(
        uint256 entropy,
        uint256 symbolCountWad,
        uint256 payoutConstantWad,
        uint256 payoutBottomLine
    ) internal pure returns (uint256) {
        // Roll a number from 1-100 inclusive
        // symbolCount / ((payoutConstant / roll)^2)
        // i.e. 6 / ((95 / roll) ^ 2)
        uint256 curve = divideWads(
            symbolCountWad,
            FixedPointMathLib.rpow(
                divideWads(payoutConstantWad, toWad((entropy % 100) + 1 + payoutBottomLine)),
                2,
                WAD
            )
        );

        return curve / WAD;
    }

    function generate(
        uint256 entropy,
        uint256 boardSize,
        uint256 symbolCount,
        uint256 payoutConstant,
        uint256 payoutBottomLine
    ) internal pure
        sizeWithinBounds(boardSize)
        symbolsWithinBounds(symbolCount)
        payoutConstantWithinBounds(payoutConstant)
    returns (uint256 out) {
        if (boardSize == 0) return 0;

        uint256 symbolCountWad = toWad(symbolCount);
        uint256 payoutConstantWad = toWad(payoutConstant);

        out |= entropyToSymbol(entropy, symbolCountWad, payoutConstantWad, payoutBottomLine);
        for (uint256 i = 1; i < boardSize; i++) {
            out = (out << 4) | entropyToSymbol((entropy >> 4 * i) + i, symbolCountWad, payoutConstantWad, payoutBottomLine);
        }

        return out;
    }

    function get(uint256 board, uint256 index) internal pure returns (uint256) {
        return (board >> 4 * index) & MASK_4;
    }

    function getWithRow(uint256 board, uint256 row, uint256 rowIndex, uint256 rowSize) internal pure returns (uint256) {
        return get(board, (row * rowSize) + rowIndex);
    }
}