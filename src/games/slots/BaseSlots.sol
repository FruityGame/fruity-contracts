// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Board } from "src/libraries/Board.sol";
import { RandomnessBeacon } from "src/randomness/RandomnessBeacon.sol";
import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";
import { JackpotResolver } from "src/games/slots/jackpot/JackpotResolver.sol";

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
abstract contract BaseSlots is RandomnessBeacon, PaymentProcessor, JackpotResolver {
    SlotParams public params;

    event BetPlaced(address indexed user, uint256 betId);
    event BetFulfilled(address indexed user, uint256 board, uint256 payoutWad);
    event BetCancelled(address indexed user, uint256 betId);

    error BetTooSmall(uint256 userCredits, uint256 minCredits);
    error BetTooLarge(uint256 userCredits, uint256 maxCredits);
    error InvalidSession(address user, uint256 betId);

    error InvalidParams(bytes message);

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
        require(symbol <= _params.symbols, "Invalid symbol parsed from board for this contract");
        _;
    }

    modifier isNotScatter(uint256 symbol, SlotParams memory _params) {
        require(symbol != _params.scatterSymbol, "Symbol cannot be a scatter symbol");
        _;
    }

    modifier sanitizeParams(SlotParams memory _params) virtual {
        _;
    }

    constructor(SlotParams memory slotParams) sanitizeParams(slotParams) {
        params = slotParams;
    }

    /*
        Core Logic
    */

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
        for (uint256 i = 0; i < _params.reels * _params.rows; ++i) {
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
}