// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/libraries/Board.sol";

library Winline {
    uint256 constant WINLINE_MASK = (0x1 << 10) - 1;

    error InvalidWinlineNibble(uint256 nibble);

    modifier indexInBounds(uint256 index, uint256 winlineSize) {
        require(winlineSize > 0, "Invalid winline size provided");
        require(index < 256 / (winlineSize * 2), "Invalid index provided");
        _;
    }

    function parseWinline(uint256 winlines, uint256 index, uint256 winlineSize) internal pure
        indexInBounds(index, winlineSize)
    returns (uint256) {
        return (winlines >> (winlineSize * 2) * index) & ((1 << winlineSize * 2) - 1);
    }

    function lineNibbleToRow(uint256 nibble) internal pure returns (uint256) {
        if (nibble == 0 || nibble > 3) revert InvalidWinlineNibble(nibble);
        return nibble - 1;
    }
}