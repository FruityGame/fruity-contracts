// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/MultiLineSlots.sol";
import "src/payment/NativePaymentProcessor.sol";
import "src/randomness/consumer/Chainlink.sol";

contract MockMuliLineSlots is MultiLineSlots, NativePaymentProcessor, ChainlinkConsumer {
    mapping(uint256 => SlotSession) public sessions;

    constructor(
        SlotParams memory slotParams,
        VRFParams memory vrfParams,
        uint256[] memory winlines
    )
        ChainlinkConsumer(vrfParams)
        MultiLineSlots(slotParams, winlines)
    {}

    function getSession(uint256 betId) internal view override
    returns (SlotSession memory session) {
        session = sessions[betId];

        if (session.betWad == 0) revert InvalidSession(session.user, betId);
    }

    function startSession(uint256 betId, SlotSession memory session) internal override {
        if (session.betWad == 0) revert InvalidSession(session.user, betId);

        sessions[betId] = session;
    }

    function endSession(uint256 betId) internal override {
        if (sessions[betId].betWad == 0) revert InvalidSession(sessions[betId].user, betId);

        sessions[betId].betWad = 0;
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

