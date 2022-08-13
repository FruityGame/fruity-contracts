// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { SlotParams } from "src/games/slots/BaseSlots.sol";

library Board {
    uint256 constant WAD = 1e18;
    uint256 constant MASK_4 = (0x1 << 4) - 1;

    modifier symbolsWithinBounds(SlotParams memory params) {
        require(params.symbols > 0 && params.symbols <= 15, "Invalid number of symbols provided");
        _;
    }

    modifier payoutConstantWithinBounds(SlotParams memory params) {
        require(params.payoutConstant > 0, "Invalid payout constant provided");
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
        // Roll a number from 1-100 inclusive and map the result
        // to a symbol number via an exponential curve
        // symbolCount / ((payoutConstant / (roll + bottomLine)) ^ 2)
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

    function generate(uint256 entropy, SlotParams memory params) internal pure
        symbolsWithinBounds(params)
        payoutConstantWithinBounds(params)
    returns (uint256 out) {
        uint256 boardSize = params.reels * params.rows;
        require(boardSize > 0 && boardSize <= 64, "Invalid board size provided");

        uint256 symbolCountWad = toWad(params.symbols);
        uint256 payoutConstantWad = toWad(params.payoutConstant);

        out |= entropyToSymbol(entropy, symbolCountWad, payoutConstantWad, params.payoutBottomLine);
        for (uint256 i = 1; i < boardSize; i++) {
            out = (out << 4) | entropyToSymbol((entropy >> 4 * i) + i, symbolCountWad, payoutConstantWad, params.payoutBottomLine);
        }

        return out;
    }

    function get(uint256 board, uint256 index) internal pure returns (uint256) {
        return (board >> 4 * index) & MASK_4;
    }

    function getFrom(
        uint256 board,
        uint256 rowIndex,
        uint256 columnIndex,
        uint256 rowLen
    ) internal pure returns (uint256) {
        return get(board, (rowIndex * rowLen) + columnIndex);
    }
}