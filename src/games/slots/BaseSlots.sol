// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { AddressRegistry } from "src/upgrades/AddressRegistry.sol";
import { RandomnessBeacon } from "src/randomness/RandomnessBeacon.sol";
import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";
import { JackpotResolver } from "src/games/slots/jackpot/JackpotResolver.sol";
import { Board } from "src/libraries/Board.sol";
import { Game } from "src/games/Game.sol";

// Largest symbol that can be parsed from each 4 bit section of the board
uint256 constant MAX_SYMBOL = 15;
// Default Jackpot is a 1/1024 chance if the largest symbol is hit
uint256 constant JACKPOT_WIN = (1 << 5) - 1;

// Solidity storage unfortunately doesn't pack nested
// structs, so all params have to go in the base contract
struct SlotParams {
    uint16 rows;
    uint16 reels;
    uint32 symbols;
    uint32 wildSymbol;
    uint32 scatterSymbol;
    uint32 bonusSymbol;
    uint32 payoutConstant;
    uint32 payoutBottomLine;
    uint16 maxBetCredits;
    uint16 maxJackpotCredits;
    uint256 creditSizeWad;
}

// Base User Game Session struct
struct SlotSession {
    address user;
    uint256 betWad;
    uint256 winlines;
    uint256 winlineCount;
}

// Base contract for other Slots contracts to derive from with core logic
abstract contract BaseSlots is RandomnessBeacon, PaymentProcessor, JackpotResolver, Game {
    SlotParams public params;

    event BetPlaced(address indexed user, uint256 betId);
    event BetFulfilled(address indexed user, uint256 board, uint256 payoutWad);
    event BetCancelled(address indexed user, uint256 betId);

    error BetTooSmall(uint256 userCredits, uint256 minCredits);
    error BetTooLarge(uint256 userCredits, uint256 maxCredits);

    error InvalidSession(address user, uint256 betId);
    error InvalidSymbol(uint256 symbol);
    error InvalidParams();

    modifier canAfford(uint256 payoutWad) virtual override {
        if (payoutWad > availableAssets()) {
            revert InsufficientFunds(address(this), availableAssets(), payoutWad);
        }
        _;
    }

    modifier isValidBet(uint256 credits) virtual {
        if (credits == 0) revert BetTooSmall(credits, 1);
        if (credits > params.maxBetCredits) revert BetTooLarge(credits, params.maxBetCredits);
        _;
    }

    modifier isValidSymbol(uint256 symbol, SlotParams memory _params) {
        if (symbol > _params.symbols) revert InvalidSymbol(symbol);
        _;
    }

    modifier isNotScatter(uint256 symbol, SlotParams memory _params) {
        if (symbol == _params.scatterSymbol) revert InvalidSymbol(symbol);
        _;
    }

    // Trying to save bytecode by not using 
    modifier sanitizeParams(SlotParams memory _params) virtual {
        if(_params.rows == 0 || _params.rows > 8 ||
         _params.reels == 0 || _params.reels > 8 ||
         _params.symbols == 0 && _params.symbols > 15 ||
         _params.payoutConstant == 0 ||
         _params.maxBetCredits == 0 ||
         _params.maxJackpotCredits == 0 ||
         _params.creditSizeWad == 0) revert InvalidParams();
        _;
    }

    constructor(SlotParams memory slotParams, AddressRegistry addressRegistry) sanitizeParams(slotParams)
        Game(addressRegistry)
    {
        params = slotParams;

        // Setup Governor role to allow Governance to configure machine params
        getRolesWithCapability[address(this)][BaseSlots.setParams.selector] |= bytes32(1 << uint8(Roles.Governor));
    }

    /*
        Core Logic
    */

    function getParams() public view returns (SlotParams memory) {
        return params;
    }

    function beginBet(SlotSession memory session) internal returns (uint256 requestId) {
        takePayment(session);

        requestId = requestRandomness();
        startSession(requestId, session);
        emit BetPlaced(session.user, requestId);
    }

    function cancelBet(uint256 requestId) public {
        SlotSession memory session = getSession(requestId);
        if (session.user != msg.sender) revert InvalidSession(msg.sender, requestId);

        emit BetCancelled(msg.sender, requestId);
        // End before refund to prevent reentrancy attacks
        endSession(requestId);
        refund(session);
    }

    function fulfillRandomness(uint256 requestId, uint256 randomness) internal virtual override {
        SlotSession memory session = getSession(requestId);
        SlotParams memory _params = params;

        takeJackpot(session, _params);

        uint256 board = Board.generate(randomness, _params);
        uint256 payoutWad = processSession(board, randomness, session, _params);

        // End session before payout to prevent reentrancy attacks
        endSession(requestId);
        // Payout remaining balance if we don't have enough to cover the win
        uint256 balanceWad = availableAssets();
        if (payoutWad > balanceWad) payoutWad = balanceWad;
        if (payoutWad > 0) payout(session.user, payoutWad);

        emit BetFulfilled(session.user, board, payoutWad);
    }

    function checkScatter(
        uint256 board,
        SlotParams memory _params
    ) internal pure virtual returns (uint256 count) {
        uint256 boardSize = _params.reels * _params.rows;
        for (uint256 i = 0; i < boardSize; ++i) {
            if (Board.get(board, i) == _params.scatterSymbol) ++count;
        }
    }

    function rollJackpot(uint256 randomness) internal pure virtual returns (bool) {
        return (randomness & JACKPOT_WIN) ^ JACKPOT_WIN == 0;
    }

    function resolveSymbol(
        uint256 symbol,
        uint256 count,
        uint256 randomness,
        SlotSession memory session,
        SlotParams memory _params
    ) internal virtual
        isValidSymbol(symbol, _params)
        isNotScatter(symbol, _params)
    returns (uint256 payoutWad) {
        if (count > _params.reels / 2) {
            if (symbol == _params.symbols && rollJackpot(randomness)) {
                payoutWad += consumeJackpot();
            }
            payoutWad += session.betWad * (
                (((symbol + 1) * MAX_SYMBOL) / (_params.symbols + 1)) *
                (count - (_params.reels / 2))
            );
        }
    }

    function processSession(
        uint256 board,
        uint256 randomness,
        SlotSession memory session,
        SlotParams memory _params
    ) internal virtual returns (uint256 payoutWad);

    /*
        Payment related methods/abstraction
    */

    function refund(SlotSession memory session) internal virtual;
    function takePayment(SlotSession memory session) internal virtual;
    function takeJackpot(SlotSession memory session, SlotParams memory _params) internal virtual;

    function payout(address user, uint256 payoutWad) internal virtual {
        _withdraw(user, payoutWad);
    }

    function availableAssets() public view virtual returns (uint256) {
        uint256 balanceWad = _balance();
        uint256 _jackpotWad = getJackpot();
        if (balanceWad < _jackpotWad) return 0;

        // Ensure we reserve the jackpot
        return balanceWad - _jackpotWad;
    }

    /*
        Game session abstraction
    */

    function getSession(uint256 betId) internal view virtual returns (SlotSession memory session);
    function startSession(uint256 betId, SlotSession memory session) internal virtual;
    function endSession(uint256 betId) internal virtual;

    /*
        Governor related methods
    */

    function setParams(SlotParams memory _params) external requiresAuth() sanitizeParams(_params) {
        params = _params;
    }
}