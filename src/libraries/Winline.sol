// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library Winline {
    error InvalidWinlineNibble(uint256 nibble);
    error InvalidWinlineLength(uint256 length);
    error InvalidWinlineIndex(uint256 index);
    error InvalidWinlineNibbleIndex(uint256 index);

    modifier winlineParamsInBounds(uint256 winlineIndex, uint256 winlineLen) {
        if (winlineLen == 0 || winlineLen > 255) revert InvalidWinlineLength(winlineLen);
        if (winlineIndex >= 256 / (winlineLen * 2)) revert InvalidWinlineIndex(winlineIndex);
        _;
    }

    modifier nibbleParamsInBounds(uint256 nibbleIndex, uint256 winlineLen) {
        if (nibbleIndex >= winlineLen) revert InvalidWinlineNibbleIndex(nibbleIndex);
        _;
    }

    function lineNibbleToRow(uint256 nibble) internal pure returns (uint256) {
        if (nibble == 0 || nibble > 3) revert InvalidWinlineNibble(nibble);
        return nibble - 1;
    }

    function getNibbleSingleLine(
        uint256 winline,
        uint256 nibbleIndex
    ) internal pure returns (uint256) {
        return lineNibbleToRow(winline >> (nibbleIndex * 2) & 3);
    }

    function getNibbleMultiLine(
        uint256 winlines,
        uint256 winlineIndex,
        uint256 nibbleIndex,
        uint256 winlineLen
    ) internal pure
        nibbleParamsInBounds(nibbleIndex, winlineLen)
    returns (uint256) {
        return lineNibbleToRow(shift(winlines, winlineIndex, winlineLen) >> (nibbleIndex * 2) & 3);
    }

    // Shift used by this function does sanity checking
    function parseWinline(uint256 winlines, uint256 winlineIndex, uint256 winlineLen) internal pure returns (uint256) {
        uint256 winlineMask = (1 << winlineLen * 2) - 1;
        return shift(winlines, winlineIndex, winlineLen) & winlineMask;
    }

    // Bitshifts the winlines to the right, extracting the next winline for use in other functions internally
    function shift(uint256 winlines, uint256 winlineIndex, uint256 winlineLen) private pure
        winlineParamsInBounds(winlineIndex, winlineLen)
    returns (uint256) {
        return winlines >> (winlineLen * 2) * winlineIndex;
    }
}