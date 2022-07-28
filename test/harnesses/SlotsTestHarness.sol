// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/BasicVideoSlots.sol";

contract SlotsTestHarness is BasicVideoSlots {
    constructor(
        address coordinator,
        address link,
        bytes32 keyHash,
        uint64 subscriptionId,
        SlotParams memory _params,
        uint8[] memory specialSymbols,
        address specialSymbolsResolver
    ) BasicVideoSlots (
        coordinator,
        link,
        keyHash,
        subscriptionId,
        _params,
        specialSymbols,
        specialSymbolsResolver
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
}