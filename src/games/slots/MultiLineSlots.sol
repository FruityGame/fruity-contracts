// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { SlotParams, SlotSession, BaseSlots } from "src/games/slots/BaseSlots.sol";

import { Winline } from "src/libraries/Winline.sol";
import { Bloom } from "src/libraries/Bloom.sol";
import { Board } from "src/libraries/Board.sol";

// A winline based contract that matches from left to right
abstract contract MultiLineSlots is BaseSlots {
    mapping(bytes32 => bool) public validWinlines;
    
    error InvalidWinlineCount(uint256 count);

    constructor(SlotParams memory slotParams, uint256[] memory winlines, address owner) BaseSlots(slotParams, owner) {
        uint256 length = winlines.length;
        if (length == 0) revert InvalidParams("Contract must be instantiated with at least 1 winline");

        for (uint256 i = 0; i < length; ++i) {
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

        if (_params.scatterSymbol <= _params.symbols) {
            checkScatter(board, _params);
        }
    }

    function checkWinline(
        uint256 board,
        uint256 winline,
        SlotParams memory _params
    ) internal pure returns(uint256 symbol, uint256 count) {
        // Set our first symbol to be the wildcard, this is overwritten in the loop later
        // on if the first symbol we parse from the board doesn't match this
        symbol = _params.wildSymbol;

        for (count = 0; count < _params.reels; ++count) {
            uint256 rowIndex = Winline.getNibbleSingleLine(winline, count);
            uint256 boardSymbol = Board.getFrom(board, rowIndex, count, _params.reels);

            // If our current symbol and the parsed symbol don't match, and the parsed symbol isn't a wild
            if (boardSymbol != symbol && boardSymbol != _params.wildSymbol) {
                // If our current symbol isn't a wildcard (see explanation above)
                if (symbol != _params.wildSymbol) break;

                // This block of logic is only ran the first time we find a symbol that isn't a
                // wildcard on the board, therefore it's not being ran each iteration
                if (boardSymbol == _params.scatterSymbol) return (0, 0);

                symbol = boardSymbol;
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

        if (count == 0) revert InvalidWinlineCount(count);
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

    function takeJackpot(SlotSession memory session, SlotParams memory _params) internal virtual override {
        addToJackpot(
            (session.betWad * session.winlineCount) / 100,
            _params.maxJackpotCredits * _params.creditSizeWad
        );
    }
}