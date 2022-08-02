// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/utils/ReentrancyGuard.sol";
import "solmate/mixins/ERC4626.sol";
import "solmate/tokens/ERC20.sol";

import "src/libraries/Winline.sol";
import "src/libraries/Bloom.sol";
import "src/libraries/Board.sol";
import "src/randomness/RandomnessBeacon.sol";
import "src/payment/PaymentProcessor.sol";

// Solidity storage unfortunately doesn't pack nested
// structs, so all params have to go in the base contract
struct SlotParams {
    uint16 rows;
    uint32 reels;
    uint32 symbols;
    uint32 wildSymbol;
    uint32 scatterSymbol;
    uint32 bonusSymbol;
    uint32 payoutConstant;
    uint32 payoutBottomLine;
    uint16 maxBetCredits;
    uint256 creditSizeWad;
}

// Base User Game Session struct
struct SlotSession {
    address user;
    uint256 betWad;
    uint256 winlines;
    uint256 winlineCount;
}

// Default Jackpot is a 1/1024 chance if the largest symbol is hit
uint256 constant JACKPOT_WIN = (1 << 5) - 1;

// A winline based contract that matches from left to right
abstract contract BaseSlots is RandomnessBeacon, PaymentProcessor, ReentrancyGuard {
    SlotParams public params;
    uint256 public jackpotWad;

    event BetPlaced(address user, uint256 betId);
    event BetFulfilled(address user, uint256 board, uint256 payoutWad);

    error BetTooSmall(uint256 userCredits, uint256 minCredits);
    error BetTooLarge(uint256 userCredits, uint256 maxCredits);
    error InvalidSession(address user, uint256 betId);

    modifier canAfford(uint256 payoutWad) override {
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

    constructor(SlotParams memory slotParams) {
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

    function cancelBet(uint256 requestId) public nonReentrant() {
        SlotSession memory session = getSession(requestId);
        if (session.user != msg.sender) revert InvalidSession(msg.sender, requestId);

        refund(session);
        endSession(requestId);
    }

    function fulfillRandomness(uint256 requestId, uint256 randomness) internal override nonReentrant() {
        SlotSession memory session = getSession(requestId);
        SlotParams memory _params = params;

        takeJackpot(session);

        uint256 board = Board.generate(randomness, _params);
        uint256 payoutWad = processSession(board, randomness, session, _params);

        if (_params.scatterSymbol <= _params.symbols) {
            checkScatter(board, _params);
        }

        // Payout remaining balance if we don't have enough to cover the win
        uint256 balanceWad = availableAssets();
        if (payoutWad > balanceWad) payoutWad = balanceWad;
        if (payoutWad > 0) payout(session.user, payoutWad);

        endSession(requestId);
        emit BetFulfilled(session.user, board, payoutWad);
    }

    function checkScatter(
        uint256 board,
        SlotParams memory _params
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < _params.reels * _params.rows; ++i) {
            if (Board.get(board, i) == _params.scatterSymbol) ++count;
        }
    }

    function resolveSymbol(
        uint256 symbol,
        uint256 count,
        uint256 randomness,
        SlotSession memory session,
        SlotParams memory _params
    ) internal virtual returns (uint256 payoutWad) {
        if (count > _params.reels / 2) {
            if (symbol == _params.symbols && (randomness & JACKPOT_WIN) ^ JACKPOT_WIN == 0) {
                payoutWad += jackpotWad;
                jackpotWad = 0;
            }
            payoutWad += session.betWad * (
                (((symbol + 1) * 15) / (_params.symbols + 1)) *
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
    function takeJackpot(SlotSession memory session) internal virtual;

    function payout(address user, uint256 payoutWad) internal virtual {
        _withdraw(user, payoutWad);
    }

    function availableAssets() public view returns (uint256) {
        uint256 balanceWad = _balance();
        if (balanceWad < jackpotWad) return 0;

        // Ensure we reserve the jackpot
        return balanceWad - jackpotWad;
    }

    /*
        Game session abstraction
    */

    function getSession(uint256 betId) internal view virtual returns (SlotSession memory session);
    function startSession(uint256 betId, SlotSession memory session) internal virtual;
    function endSession(uint256 betId) internal virtual;
}