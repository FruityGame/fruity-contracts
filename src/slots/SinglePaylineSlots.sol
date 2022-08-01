// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/BaseSlots.sol";

// Optimised for single paylines only (although not bytecode optimised lol)
abstract contract SinglePaylineSlots is BaseSlots {
    uint256 private immutable WINLINE;

    constructor(
        SlotParams memory slotParams,
        VaultParams memory vaultParams
    ) BaseSlots(slotParams, vaultParams, getInitialWinlines()) {
        WINLINE = constructWinline(slotParams.reels);
    }

    function placeBet(uint256 credits, uint256 winlines) public payable override
        isValidBet(credits)
    returns (uint256 requestId) {
        super.placeBet(credits, WINLINE);
    }

    function countWinlines(
        uint256 winlines,
        uint256 reelCount
    ) internal view override returns (uint256 out) {
        out = 1;
    }

    function constructWinline(uint256 reelCount) private pure returns (uint256 winline) {
        while(--reelCount > 0) {
            winline |= 2 << 2 * reelCount;
        }
        winline |= 2;
    }

    function getInitialWinlines() private pure returns (uint256[] memory out) {}
}