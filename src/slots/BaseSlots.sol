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
    uint16 maxBet;
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
        if (payoutWad > availableAssets()) {
            revert InsufficientFunds(availableAssets(), payoutWad);
        }
        _;
    }

    modifier isValidJackpot() {
        if (totalAssets() < jackpotWad) {
            revert InsufficientFunds(availableAssets(), jackpotWad);
        }
        _;
    }

    modifier isValidBet(uint256 credits) virtual {
        if (credits == 0) revert BetTooSmall(credits, 1);
        if (credits > params.maxBet) revert BetTooLarge(credits, params.maxBet);
        _;
    }

    modifier isZeroMsgValue() {
        require(msg.value == 0, "Contract doesn't accept the native token");
        _;
    }

    constructor(
        SlotParams memory slotParams,
        VaultParams memory vaultParams,
        uint256[] memory winlines
    ) ERC4626(ERC20(vaultParams.asset), vaultParams.name, vaultParams.symbol) {
        for (uint256 i = 0; i < winlines.length; i++) {
            validWinlines[bytes32(winlines[i])] = true;
        }

        params = slotParams;
    }

    /*
        Implement ERC4626 methods
    */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /*
        Payment related methods
    */
    function refund(address user, uint256 refundWad) internal virtual canAfford(refundWad) {
        asset.transfer(user, refundWad);
    }

    function payout(address user, uint256 payoutWad) internal virtual canAfford(payoutWad) {
        asset.transfer(user, payoutWad);
    }

    function takePayment(address user, uint256 paymentWad) internal virtual {
        asset.transferFrom(user, address(this), paymentWad);
    }

    function availableAssets() public view virtual
        isValidJackpot()
    returns (uint256) {
        return totalAssets() - jackpotWad;
    }

    /*
        Game session abstraction
    */
    function getSession(uint256 betId) internal view virtual returns (SlotSession memory session);
    function startSession(uint256 betId, SlotSession memory session) internal virtual;
    function endSession(uint256 betId) internal virtual;

    function takeJackpot(uint256 betWad) internal virtual {
        jackpotWad += (betWad / 100);
    }

    // I hate that it's more efficient on gas to do it this way (re: the arguments)
    function resolveSymbol(
        uint256 betWad,
        uint256 symbol,
        uint256 count,
        uint256 symbolCount,
        uint256 reelCount,
        uint256 randomness
    ) internal virtual returns (uint256 payoutWad) {
        if (count > reelCount / 2) {
            if (symbol == symbolCount && (randomness & JACKPOT_WIN) ^ JACKPOT_WIN == 0) {
                payoutWad += jackpotWad;
                jackpotWad = 0;
            }
            payoutWad += betWad * (
                (((symbol + 1) * 15) / (symbolCount + 1)) *
                (count - (reelCount / 2))
            );
        }
    }

    function placeBet(uint256 credits, uint256 winlines) public payable virtual
        isValidJackpot()
        isValidBet(credits)
        isZeroMsgValue()
    returns (uint256 requestId) {
        if (msg.value > 0) {
            
        }
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

    function fulfillRandomness(uint256 requestId, uint256 randomness) internal override
        isValidJackpot()
        nonReentrant()
    {
        SlotSession memory session = getSession(requestId);
        SlotParams memory _params = params;

        uint256 board = Board.generate(
            randomness,
            _params.rows,
            _params.reels,
            _params.symbols,
            _params.payoutConstant,
            _params.payoutBottomLine
        );
        uint256 payoutWad = 0;

        takeJackpot(session.betWad * session.winlineCount);

        for (uint256 i = 0; i < session.winlineCount; i++) {
            uint256 winline = Winline.parseWinline(session.winlines, i, _params.reels);
            (uint256 symbol, uint256 count) = checkWinline(
                board,
                winline,
                _params.reels,
                _params.wildSymbol
            );

            require(symbol <= _params.symbols, "Invalid symbol parsed from board for this contract");
            payoutWad += resolveSymbol(session.betWad, symbol, count, _params.symbols, _params.reels, randomness);
        }

        if (_params.scatterSymbol != 0) {
            checkScatter(board, _params.reels * _params.rows, _params.scatterSymbol);
        }

        // Payout remaining balance if we don't have enough to cover the win
        if (payoutWad > availableAssets()) payoutWad = availableAssets();
        if (payoutWad > 0) payout(session.user, payoutWad);

        endSession(requestId);
        emit BetFulfilled(session.user, board, payoutWad);
    }

    function checkScatter(
        uint256 board,
        uint256 boardLen,
        uint256 scatterSymbol
    ) internal pure returns (uint256 count) {
        while (--boardLen > 0) {
            if (Board.get(board, boardLen) == scatterSymbol) count++;
        }
    }

    function checkWinline(
        uint256 board,
        uint256 winline,
        uint256 reelCount,
        uint256 wildSymbol
    ) internal pure virtual returns(uint256 symbol, uint256 count) {
        symbol = wildSymbol;
        for (uint256 reelIndex = 0; reelIndex < reelCount; reelIndex++) {
            uint256 rowIndex = Winline.getNibbleSingleLine(winline, reelIndex);
            uint256 boardSymbol = Board.getFrom(board, rowIndex, reelIndex, reelCount);

            // If we've got no match and the symbol on the board isn't a Wildcard
            if (boardSymbol != symbol && boardSymbol != wildSymbol) {
                // If our current symbol isn't a wildcard, STOP THE COUNT
                if (symbol != wildSymbol) {
                    break;
                }
                // Reaching here implies we started off with a Wildcard
                // replace that with the symbol we just found and continue
                symbol = boardSymbol;
            }

            count += 1;
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
            count += 1;
        }
    }
}