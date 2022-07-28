// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/BasicSlots.sol";

contract SlotsTestHarness is BasicSlots {
    uint256 expectedSpecialSymbol = 0;

    constructor(
        VRFParams memory vrfParams,
        SlotParams memory _params,
        uint8[] memory specialSymbols
    ) BasicSlots (
        vrfParams,
        _params,
        specialSymbols
    ) {}

    function checkWinlineExternal(uint256 board, uint256 winline) external view returns(uint256, uint256) {
        return checkWinline(board, winline);
    }

    function countWinlinesExternal(uint256 winlines) external view returns (uint256 count) {
        return countWinlines(winlines);
    }

    function fulfillRandomnessExternal(uint256 randomness, uint256 id) external {
        return fulfillRandomness(id, randomness);
    }

    function setExpectedSpecialSymbol(uint256 symbol) external {
        expectedSpecialSymbol = symbol;
    }
}