// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/BaseSlots.sol";
import "src/slots/jackpot/LocalJackpotResolver.sol";

contract MockBaseSlots is BaseSlots, LocalJackpotResolver {
    uint256 public processSessionResult = 0;
    uint256 public balance = 0;

    SlotSession session;
    bool public endSessionCalled = false;

    constructor(
        SlotParams memory slotParams
    )
        BaseSlots(slotParams)
    {}

    /*
        BaseSlots Method Mocks
    */
    function processSession(
        uint256 board,
        uint256 randomness,
        SlotSession memory _session,
        SlotParams memory _params
    ) internal override returns (uint256 payoutWad) {
        return processSessionResult;
    }

    function checkScatter(
        uint256 board,
        SlotParams memory _params
    ) internal pure override returns (uint256 count) {
        require(_params.scatterSymbol <= _params.symbols, "checkScatter called without a scatter symbol set");
        return super.checkScatter(board, _params);
    }

    function refund(SlotSession memory _session) internal override {
        require(endSessionCalled, "Attempted to refund before the session was ended");
        _withdraw(_session.user, _session.betWad);
    }

    function takePayment(SlotSession memory _session) internal override {
        _deposit(_session.user, _session.betWad);
    }

    function takeJackpot(SlotSession memory _session) internal override {
        jackpotWad += _session.betWad / 3;
    }

    function getSession(uint256 betId) internal view override
    returns (SlotSession memory _session) {
        require(betId == 1, "Invalid BetID in Mock");
        if (endSessionCalled) revert InvalidSession(address(0), betId);

        _session = session;
    }

    function startSession(uint256 betId, SlotSession memory _session) internal override {
        require(betId == 1, "Invalid BetID in Mock");
        session = _session;
    }

    function endSession(uint256 betId) internal override {
        require(betId == 1, "Invalid BetID in Mock");
        if (endSessionCalled) revert InvalidSession(address(0), betId);

        endSessionCalled = true;
    }

    /*
        VRF Mocks
    */
    function requestRandomness() internal override returns (uint256) {
        // Fixed betID of 1
        return 1;
    }

    /*
        Payment Processor mocks
    */
    function _deposit(address from, uint256 paymentWad) internal override {
        balance += paymentWad;
    }

    function _withdraw(address to, uint256 paymentWad) internal override {
        require(endSessionCalled, "Attempted to payout before the session was ended");
        balance -= paymentWad;
    }

    function _balance() internal view override returns (uint256) {
        return balance;
    }

    /*
        Methods to expose internal logic for testing
    */

    function beginBetExternal(SlotSession memory _session) external returns (uint256 requestId) {
        return beginBet(_session);
    }

    function checkScatterExternal(uint256 board) external view returns(uint256) {
        return checkScatter(board, params);
    }

    function resolveSymbolExternal(
        uint256 symbol,
        uint256 count,
        uint256 randomness,
        SlotSession memory _session,
        SlotParams memory _params
    ) external returns(uint256) {
        return resolveSymbol(symbol, count, randomness, _session, _params);
    }

    function fulfillRandomnessExternal(uint256 id, uint256 randomness) external {
        return fulfillRandomness(id, randomness);
    }

    function getParams() external view returns (SlotParams memory _params) {
        return params;
    }

    /*
        Methods to set mock values for internal logic testing
    */
    function setProcessSessionResult(uint256 result) external {
        processSessionResult = result;
    }

    function setJackpot(uint256 jackpot) external {
        jackpotWad = jackpot;
    }

    function setBalance(uint256 balanceWad) external {
        balance = balanceWad;
    }
}

