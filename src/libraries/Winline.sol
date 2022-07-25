// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/libraries/Board.sol";

library Winline {
    uint256 constant WINLINE_MASK = (0x1 << 10) - 1;

    error InvalidWinlineNibble(uint256 nibble);
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

    function parseWinline(uint256 winlines, uint256 index) external pure returns (uint256) {
        require(index < 25, "Invalid index provided");
        return (winlines >> 10 * index) & WINLINE_MASK;
    }

    function lineNibbleToRow(uint256 nibble) external pure returns (uint256) {
        // 0b01 || 0b00
        // Second bit unset (no row shift)
        if (nibble == 1) return 0;
        // 0b10
        // Second bit set (implies a row shift), first bit unset (second row)
        if (nibble == 2) return 1;
        // 0b11
        // Second bit set (implies a row shift), first bit set (third row)
        if (nibble == 3) return 2;

        revert InvalidWinlineNibble(nibble);
    }
}