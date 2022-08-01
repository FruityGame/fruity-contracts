// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/BaseSlots.sol";
import "src/randomness/consumer/Chainlink.sol";

uint256 constant ACTIVE_SESSION = 1 << 255;
uint256 constant WINLINE_COUNT_MASK = (1 << 254) - 1;

contract MockBaseSlots is BaseSlots, ChainlinkConsumer {
    mapping(uint256 => SlotSession) public sessions;

    constructor(
        SlotParams memory slotParams,
        VaultParams memory vaultParams,
        VRFParams memory vrfParams,
        uint256[] memory winlines
    )
        ChainlinkConsumer(vrfParams)
        BaseSlots(
            slotParams,
            vaultParams,
            winlines
        )
    {}

    function getSession(uint256 betId) internal view override
    returns (SlotSession memory session) {
        session = sessions[betId];

        if (session.winlineCount & ACTIVE_SESSION != ACTIVE_SESSION) {
            revert InvalidSession(session.user, betId);
        }

        // Omit the session lock bit from the returned winline count
        session.winlineCount &= WINLINE_COUNT_MASK;
    }

    function startSession(uint256 betId, SlotSession memory session) internal override {
        if (session.winlineCount & ACTIVE_SESSION == ACTIVE_SESSION) {
            revert InvalidSession(session.user, betId);
        }

        session.winlineCount |= ACTIVE_SESSION;
        sessions[betId] = session;
    }

    function endSession(uint256 betId) internal override {
        if (sessions[betId].winlineCount & ACTIVE_SESSION != ACTIVE_SESSION) {
            revert InvalidSession(sessions[betId].user, betId);
        }

        sessions[betId].winlineCount ^= ACTIVE_SESSION;
    }

    /*
        Methods to expose internal logic for testing
    */
    function checkWinlineExternal(uint256 board, uint256 winline) external view returns(uint256, uint256) {
        return checkWinline(board, winline, params);
    }

    function checkScatterExternal(uint256 board) external view returns(uint256) {
        return checkScatter(board, params);
    }

    function countWinlinesExternal(uint256 winlines) external view returns (uint256 count) {
        return countWinlines(winlines, params.reels);
    }

    function fulfillRandomnessExternal(uint256 id, uint256 randomness) external {
        return fulfillRandomness(id, randomness);
    }
}

