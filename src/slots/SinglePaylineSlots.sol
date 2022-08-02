// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/BaseSlots.sol";

// Optimised for single paylines only (although not bytecode optimised lol)
abstract contract SinglePaylineSlots is BaseSlots {
    constructor(
        SlotParams memory slotParams
    ) BaseSlots(slotParams) {}

    /*
        Core Logic
    */
    function placeBet(uint256 credits) public payable
        isValidBet(credits)
    returns (uint256 requestId) {
        return beginBet(
            SlotSession(msg.sender, credits * params.creditSizeWad, 0, 0)
        );
    }

    function processSession(
        uint256 board,
        uint256 randomness,
        SlotSession memory session,
        SlotParams memory _params
    ) internal override returns (uint256 payoutWad) {
        (uint256 symbol, uint256 count) = checkWinline(board, _params);
        payoutWad += resolveSymbol(symbol, count, randomness, session, _params);
    }

    function checkWinline(
        uint256 board,
        SlotParams memory _params
    ) internal pure returns(uint256 symbol, uint256 count) {
        // Get the starting symbol from the board
        uint256 middleRow = _params.rows / 2;
        symbol = Board.getFrom(board, middleRow, 0, _params.reels);
        require(symbol <= _params.symbols, "Invalid symbol parsed from board for this contract");
        if (symbol == _params.scatterSymbol) return (0, 0); // Don't want to parse scatters

        for (count = 1; count < _params.reels; ++count) {
            uint256 boardSymbol = Board.getFrom(board, middleRow, count, _params.reels);

            // If we've got no match and the symbol on the board isn't a Wildcard, STOP THE COUNT
            if (boardSymbol != symbol && boardSymbol != _params.wildSymbol) {
                break;
            }
        }
    }

    /*
        Payment related methods
    */
    function refund(SlotSession memory session) internal override {
        _withdraw(session.user, session.betWad);
    }

    function takePayment(SlotSession memory session) internal override {
        _deposit(session.user, session.betWad);
    }

    function takeJackpot(SlotSession memory session) internal override {
        jackpotWad += (session.betWad / 100);
    }
}