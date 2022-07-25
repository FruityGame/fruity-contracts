// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/BasicVideoSlots.sol";

contract SlotsTestHarness is BasicVideoSlots {
    constructor(
        address coordinator,
        address link,
        bytes32 keyHash,
        uint64 subscriptionId
    ) BasicVideoSlots (
        coordinator,
        link,
        keyHash,
        subscriptionId
    ) {}

    function checkWinlineExternal(uint256 board, uint256 winline) external pure returns(uint256, uint256) {
        return checkWinline(board, winline);
    }
}