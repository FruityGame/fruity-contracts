// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { AddressRegistry } from "src/upgrades/AddressRegistry.sol";
import { SlotParams, SlotSession, BaseSlots } from "src/games/slots/BaseSlots.sol";
import { Board } from "src/libraries/Board.sol";

// Optimised for single paylines only
abstract contract SingleLineSlots is BaseSlots {
    constructor(
        SlotParams memory slotParams,
        AddressRegistry addressRegistry
    ) BaseSlots(slotParams, addressRegistry) {
        // Setup Relayer role to allow SessionRelayer to proxy calls to this contract
        getRolesWithCapability[address(this)][this.placeBetProxy.selector] |= bytes32(1 << uint8(Roles.Relayer));
    }

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

    // Should not be payable since the Proxy cannot forward on Eth
    function placeBetProxy(address user, uint256 credits) public
        requiresAuth() // Can only be called by the SessionRelayer
        isValidBet(credits)
    returns (uint256 requestId) {
        return beginBet(
            SlotSession(user, credits * params.creditSizeWad, 0, 0)
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

        if (_params.scatterSymbol <= _params.symbols) {
            checkScatter(board, _params);
        }
    }

    function checkWinline(
        uint256 board,
        SlotParams memory _params
    ) internal pure returns(uint256 symbol, uint256 count) {
        // Get the middle most row of our slots
        uint256 middleRow = _params.rows / 2;

        // Set our first symbol to be the wildcard, this is overwritten in the loop later
        // on if the first symbol we parse from the board doesn't match this
        symbol = _params.wildSymbol;
        for (count = 0; count < _params.reels; ++count) {
            // Get from the middleRow index only
            uint256 boardSymbol = Board.getFrom(board, middleRow, count, _params.reels);

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

    /*
        Payment related methods
    */
    function refund(SlotSession memory session) internal override {
        _withdraw(session.user, session.betWad);
    }

    function takePayment(SlotSession memory session) internal override {
        _deposit(session.user, session.betWad);
    }

    function takeJackpot(SlotSession memory session, SlotParams memory _params) internal virtual override {
        addToJackpot(
            session.betWad / 100,
            _params.maxJackpotCredits * _params.creditSizeWad
        );
    }
}