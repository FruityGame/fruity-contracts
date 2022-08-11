// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/games/slots/MultiLineSlots.sol";

import "test/mocks/games/slots/jackpot/MockLocalJackpotResolver.sol";
import "test/mocks/payment/MockPaymentProcessor.sol";
import "test/mocks/MockVRF.sol";

contract MockMuliLineSlots is MultiLineSlots, MockLocalJackpotResolver, MockPaymentProcessor, MockVRF {
    mapping(uint256 => SlotSession) public sessions;

    constructor(
        SlotParams memory slotParams,
        uint256[] memory winlines,
        address owner
    )
        MultiLineSlots(slotParams, winlines, owner)
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

    function countWinlinesExternal(uint256 winlines) external view returns (uint256 count) {
        return countWinlines(winlines, params.reels);
    }

    function getParams() external view returns (SlotParams memory) {
        return params;
    }

    /*
        Mock related methods
    */
}

