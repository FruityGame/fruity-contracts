// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/BaseSlots.sol";

import "src/libraries/Winline.sol";
import "src/libraries/Bloom.sol";
import "src/libraries/Board.sol";

// A winline based contract that matches from left to right
abstract contract MultiLineSlots is BaseSlots {
    mapping(bytes32 => bool) public validWinlines;

    constructor(SlotParams memory slotParams, uint256[] memory winlines) BaseSlots(slotParams) {
        for (uint256 i = 0; i < winlines.length; ++i) {
            validWinlines[bytes32(winlines[i])] = true;
        }
    }

    /*
        Core Logic
    */
    function placeBet(uint256 credits, uint256 winlines) public payable
        isValidBet(credits)
    returns (uint256 requestId) {
        return beginBet(
            SlotSession(
                msg.sender,
                credits * params.creditSizeWad,
                winlines,
                countWinlines(winlines, params.reels)
            )
        );
    }

    function processSession(
        uint256 board,
        uint256 randomness,
        SlotSession memory session,
        SlotParams memory _params
    ) internal override returns (uint256 payoutWad) {
        for (uint256 i = 0; i < session.winlineCount; ++i) {
            uint256 winline = Winline.parseWinline(session.winlines, i, _params.reels);
            (uint256 symbol, uint256 count) = checkWinline(board, winline, _params);

            payoutWad += resolveSymbol(symbol, count, randomness, session, _params);
        }
    }

    function checkWinline(
        uint256 board,
        uint256 winline,
        SlotParams memory _params
    ) internal pure returns(uint256 symbol, uint256 count) {
        // Get the starting symbol from the board
        symbol = Board.getFrom(board, Winline.getNibbleSingleLine(winline, 0), 0, _params.reels);
        require(symbol <= _params.symbols, "Invalid symbol parsed from board for this contract");
        if (symbol == _params.scatterSymbol) return (0, 0); // Don't want to parse scatters

        for (count = 1; count < _params.reels; ++count) {
            uint256 rowIndex = Winline.getNibbleSingleLine(winline, count);
            uint256 boardSymbol = Board.getFrom(board, rowIndex, count, _params.reels);

            // If we've got no match and the symbol on the board isn't a Wildcard, STOP THE COUNT
            if (boardSymbol != symbol && boardSymbol != _params.wildSymbol) {
                break;
            }
        }
    }

    // Count the number of winlines, whilst ensuring that they're unique
    function countWinlines(
        uint256 winlines,
        uint256 reelCount
    ) internal view returns (uint256 count) {
        uint256 bloom = 0;

        // While we have a winline (check the last two LSBs)
        while(winlines & 3 != 0) {
            bytes32 entry = bytes32(Winline.parseWinline(winlines, 0, reelCount));
            require(validWinlines[entry], "Invalid winline parsed for contract");
            // Ensure the winline isn't a duplicate
            bloom = Bloom.insertChecked(bloom, entry);
            // Shift over to the next winline
            winlines = winlines >> (reelCount * 2);
            ++count;
        }
    }

    /*
        Payment related methods
    */
    function refund(SlotSession memory session) internal override {
        _withdraw(session.user, session.betWad * session.winlineCount);
    }

    function takePayment(SlotSession memory session) internal override {
        _deposit(session.user, session.betWad * session.winlineCount);
    }

    function takeJackpot(SlotSession memory session) internal override {
        jackpotWad += ((session.betWad * session.winlineCount) / 100);
    }
}