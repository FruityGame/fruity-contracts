// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/utils/ReentrancyGuard.sol";
import "solmate/mixins/ERC4626.sol";
import "solmate/tokens/ERC20.sol";

import "src/libraries/Winline.sol";
import "src/libraries/Bloom.sol";
import "src/libraries/Board.sol";
import "src/randomness/RandomnessBeacon.sol";

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

struct VaultParams {
    address asset;
    string name;
    string symbol;
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
abstract contract BaseSlots is RandomnessBeacon, ReentrancyGuard, ERC4626 {
    SlotParams public params;
    mapping(bytes32 => bool) public validWinlines;

    uint256 public jackpotWad;

    event BetPlaced(address user, uint256 betId);
    event BetFulfilled(address user, uint256 board, uint256 payoutWad);

    error RefundError(address user, uint256 refundWad);
    error PayoutError(address user, uint256 payoutWad);
    error BetTooSmall(uint256 userCredits, uint256 minCredits);
    error BetTooLarge(uint256 userCredits, uint256 maxCredits);
    error InsufficientFunds(uint256 balance, uint256 wanted);
    error InvalidSession(address user, uint256 betId);

    modifier canAfford(uint256 payoutWad) {
        if (payoutWad > totalAssets()) {
            revert InsufficientFunds(totalAssets(), payoutWad);
        }
        _;
    }

    modifier isValidBet(uint256 credits) {
        if (credits == 0) revert BetTooSmall(credits, 1);
        if (credits > params.maxBetCredits) revert BetTooLarge(credits, params.maxBetCredits);
        _;
    }

    // Base Contract is ERC20 only, but placeBet needs to impl Payable for the Native Token impl.
    // Ensure we have no msg.value so it doesn't get depositied into ERC4626 vault
    modifier isZeroMsgValue() {
        require(msg.value == 0, "Contract doesn't accept the native token");
        _;
    }

    constructor(
        SlotParams memory slotParams,
        VaultParams memory vaultParams,
        uint256[] memory winlines
    ) ERC4626(ERC20(vaultParams.asset), vaultParams.name, vaultParams.symbol) {
        for (uint256 i = 0; i < winlines.length; ++i) {
            validWinlines[bytes32(winlines[i])] = true;
        }

        params = slotParams;
    }

    /*
        Implement ERC4626 methods
    */
    function totalAssets() public view override returns (uint256) {
        uint256 balanceWad = asset.balanceOf(address(this));
        if (balanceWad < jackpotWad) return 0;

        // Ensure we reserve the jackpot
        return balanceWad - jackpotWad;
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal override canAfford(assets) {}

    /*
        Payment related methods
    */
    function refund(address user, uint256 refundWad) internal virtual canAfford(refundWad) {
        asset.transfer(user, refundWad);
    }

    function payout(address user, uint256 payoutWad) internal virtual canAfford(payoutWad) {
        asset.transfer(user, payoutWad);
    }

    function takePayment(address user, uint256 paymentWad) internal virtual isZeroMsgValue() {
        asset.transferFrom(user, address(this), paymentWad);
    }

    function takeJackpot(uint256 betWad) internal virtual {
        jackpotWad += (betWad / 100);
    }

    /*
        Game session abstraction
    */
    function getSession(uint256 betId) internal view virtual returns (SlotSession memory session);
    function startSession(uint256 betId, SlotSession memory session) internal virtual;
    function endSession(uint256 betId) internal virtual;

    function resolveSymbol(
        uint256 symbol,
        uint256 count,
        uint256 randomness,
        SlotSession memory session,
        SlotParams memory params
    ) internal virtual returns (uint256 payoutWad) {
        if (count > params.reels / 2) {
            if (symbol == params.symbols && (randomness & JACKPOT_WIN) ^ JACKPOT_WIN == 0) {
                payoutWad += jackpotWad;
                jackpotWad = 0;
            }
            payoutWad += session.betWad * (
                (((symbol + 1) * 15) / (params.symbols + 1)) *
                (count - (params.reels / 2))
            );
        }
    }

    /*
        Core Logic
    */
    function placeBet(uint256 credits, uint256 winlines) public payable virtual
        isValidBet(credits)
    returns (uint256 requestId) {
        // Each winline applies a flat multiplier to the cost of the bet
        uint256 winlineCount = countWinlines(winlines, params.reels);
        uint256 betWad = credits * params.creditSizeWad;

        takePayment(msg.sender, betWad * winlineCount);

        requestId = requestRandomness();
        startSession(requestId, SlotSession(msg.sender, betWad, winlines, winlineCount));
        emit BetPlaced(msg.sender, requestId);
    }

    function cancelBet(uint256 requestId) public nonReentrant() {
        SlotSession memory session = getSession(requestId);
        require(session.user == msg.sender, "Invalid session requested for user");

        // All methods of this contract are protected from reentrancy, therefore
        // changing requests AFTER the call to transfer the funds is okay
        uint256 refundAmount = session.betWad * session.winlineCount;
        refund(session.user, refundAmount);
        endSession(requestId);
    }

    function fulfillRandomness(uint256 requestId, uint256 randomness) internal override nonReentrant() {
        SlotSession memory session = getSession(requestId);
        SlotParams memory _params = params;

        uint256 board = Board.generate(randomness, _params);
        uint256 payoutWad = 0;

        takeJackpot(session.betWad * session.winlineCount);

        for (uint256 i = 0; i < session.winlineCount; ++i) {
            uint256 winline = Winline.parseWinline(session.winlines, i, _params.reels);
            (uint256 symbol, uint256 count) = checkWinline(board, winline, _params);

            require(symbol <= _params.symbols, "Invalid symbol parsed from board for this contract");
            payoutWad += resolveSymbol(symbol, count, randomness, session, _params);
        }

        if (_params.scatterSymbol <= params.symbols) {
            checkScatter(board, _params);
        }

        // Payout remaining balance if we don't have enough to cover the win
        uint256 balanceWad = totalAssets();
        if (payoutWad > balanceWad) payoutWad = balanceWad;
        if (payoutWad > 0) payout(session.user, payoutWad);

        endSession(requestId);
        emit BetFulfilled(session.user, board, payoutWad);
    }

    function checkScatter(
        uint256 board,
        SlotParams memory params
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < params.reels * params.rows; ++i) {
            if (Board.get(board, i) == params.scatterSymbol) ++count;
        }
    }

    function checkWinline(
        uint256 board,
        uint256 winline,
        SlotParams memory params
    ) internal pure virtual returns(uint256 symbol, uint256 count) {
        // Get the starting symbol from the board
        symbol = Board.getFrom(board, Winline.getNibbleSingleLine(winline, 0), 0, params.reels);
        if (symbol == params.scatterSymbol) return (0, 0); // Don't want to parse scatters

        for (count = 1; count < params.reels; ++count) {
            uint256 rowIndex = Winline.getNibbleSingleLine(winline, count);
            uint256 boardSymbol = Board.getFrom(board, rowIndex, count, params.reels);

            // If we've got no match and the symbol on the board isn't a Wildcard, STOP THE COUNT
            if (boardSymbol != symbol && boardSymbol != params.wildSymbol) {
                break;
            }
        }
    }

    // Count the number of winlines, whilst ensuring that they're unique
    function countWinlines(
        uint256 winlines,
        uint256 reelCount
    ) internal view virtual returns (uint256 count) {
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

    function getParams() public view returns (SlotParams memory) {
        return params;
    }
}