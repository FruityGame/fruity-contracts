// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/libraries/Board.sol";

library Winline {
    event log(uint256 num);
    uint256 constant WINLINE_MASK = (0x1 << 10) - 1;
    // Really awful (I mean great) pseudo binary search algorithm
    // will find the length of an 'array' in around 5 searches for
    // a bitfield, assuming all elements are stored sequentially
    function count(uint256 winlines) external pure returns (uint256) {
        uint256 range = 8;
        uint256 num = 12;
        while(range > 0) {
            // Check if the current index has a winline by checking if
            // any of the last two bits are set. If so, traverse upwards
            if ((winlines >> 10 * num) & 0x3 != 0) {
                num += range;
            } else {
                if (num == 0) return num;
                num -= range;
            }

            range /= 2;
        }

        if ((winlines >> 10 * num) & 0x3 != 0) {
            return num + 1;
        }

        return num;
    }

    function check(uint256 board, uint256 winlines, uint256 index) external pure returns(uint256, uint256) {
        require(index < 25, "Invalid index provided");
        uint256 winline = (winlines >> 10 * index) & WINLINE_MASK;
        require(winline & 3 != 0, "Invalid winline provided");

        uint8[7] memory results = [0, 0, 0, 0, 0, 0, 0];

        results[getFromBoard(board, lineNibbleToRow((winline >> 8) & 3), 4)] += 1;
        results[getFromBoard(board, lineNibbleToRow((winline >> 6) & 3), 3)] += 1;
        results[getFromBoard(board, lineNibbleToRow((winline >> 4) & 3), 2)] += 1;
        results[getFromBoard(board, lineNibbleToRow((winline >> 2) & 3), 1)] += 1;
        results[getFromBoard(board, lineNibbleToRow((winline >> 0) & 3), 0)] += 1;

        if (results[6] > 2) return (6, results[6]);
        if (results[5] > 2) return (5, results[5]);
        if (results[4] > 2) return (4, results[4]);
        if (results[3] > 2) return (3, results[3]);
        if (results[2] > 2) return (2, results[2]);
        if (results[1] > 2) return (1, results[1]);
        return (0, results[0]);
    }

    function lineNibbleToRow(uint256 nibble) internal pure returns (uint256) {
        // 0b01 || 0b00
        // Second bit unset (no row shift)
        if (nibble < 2) return 0;
        // 0b10
        // Second bit set (implies a row shift), first bit unset (second row)
        if (nibble < 3) return 1;
        // 0b11
        // Second bit set (implies a row shift), first bit set (third row)
        return 2;
    }

    function getFromBoard(uint256 board, uint256 row, uint256 index) internal pure returns (uint256 out) {
        out = Board.get(board, row, index);
        require(out < 7, "Invalid number parsed from board for this Winline library");
    }
}