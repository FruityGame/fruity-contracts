// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "src/libraries/Winline.sol";
import "src/libraries/Board.sol";
import "src/libraries/Bloom.sol";
import "src/randomness/consumer/Chainlink.sol";

// A 'Session' is a potentially active user request,
// containing their address, bet, and winlines. To
// be used in the VRF callback
struct Session {
    address user;
    uint256 betWad;
    uint256 winlines;
    uint256 winlineCount;
}

// Params for the slot machine
struct SlotParams {
    uint64 boardSize;
    uint64 rowSize;
    uint64 symbolCount;
    uint64 payoutConstant;
    uint256 minimumBetWad;
}

// Flag used to denote an active or fulfilled session
uint256 constant WINLINE_SESSION_FLAG = 1 << 255;
// Subsequent mask for the max value of a winline, as per the above flag
uint256 constant WINLINE_COUNT_MASK = (1 << 254) - 1;

contract BasicVideoSlots is RandomnessConsumer, ReentrancyGuard {
    uint256 public jackpotWad = 0;
    SlotParams public params;

    // Mapping of chainlink RequestId's to User Sessions
    mapping(uint256 => Session) private sessions;

    event BetPlaced(address user, uint256 betId);
    event BetFulfilled(address user, uint256 board, uint256 jackpotWad);

    error BetTooSmall(uint256 betWad, uint256 wanted);

    constructor(
        address coordinator,
        address link,
        bytes32 keyHash,
        uint64 subscriptionId,
        SlotParams memory _params
    ) RandomnessConsumer(
        coordinator,
        link,
        keyHash,
        subscriptionId
    ) {
        params = _params;
    }

    modifier isValidBet(uint256 betWad) {
        if (betWad < params.minimumBetWad) revert BetTooSmall(betWad, params.minimumBetWad);
        _;
    }

    function placeBet(uint256 betWad, uint256 winlines) public payable
        isValidBet(betWad)
    returns (uint256) {
        // Each winline applies a flat multiplier to the cost of the bet
        uint256 winlineCount = countWinlines(winlines);
        uint256 totalBet = betWad * winlineCount;
        require(msg.value >= totalBet, "Amount provided not enough to cover bet");

        // Initiate a new VRF Request for the user
        uint256 requestId = requestRandomness();
        // Setup the WINLINE_SESSION_FLAG. This bit is set when a session is active,
        // unset when a session is resolved. The logic is inverted as empty mappings in solidity
        // map to 0. If using 1 as true and 0 as false, a user could potentially invoke a race condition
        // between them cancelling the bet, and the VRF fulfillment.
        // It's safe to reuse it in this way because it's impossible to ever get
        // greater than 2**254 - 1 as the winlineCount value
        winlineCount |= WINLINE_SESSION_FLAG;
        // Create a new User session associated with the VRF RequestId for the user
        // directly using requests[msg.sender] is fine for gas as we just accessed it above
        sessions[requestId] = Session(msg.sender, betWad, winlines, winlineCount);
        emit BetPlaced(msg.sender, requestId);
        return requestId;
    }

    // Jackpot is only calculated and changed if the vrf fulfillment succeeds,
    // therefore we don't need to change its value in accordance with cancelling the bet
    function cancelBet(uint256 requestId) public nonReentrant() {
        // Get the currently active session for the sender
        Session storage session = sessions[requestId];
        // Ensure the session has not already been resolved/consumed
        require(session.winlineCount & WINLINE_SESSION_FLAG == WINLINE_SESSION_FLAG, "Cannot cancel already fulfilled bet");
        // Ensure the user is the owner of the Session
        require(session.user == msg.sender, "Invalid session requested for user");
        // All methods of this contract are protected from reentrancy, therefore
        // changing requests AFTER the call to transfer the funds is okay
        (bool success, ) = session.user.call{
            value: session.betWad * (session.winlineCount & WINLINE_COUNT_MASK) // Get with the mask to omit the session lock bit
        } ("");
        require(success, "Failed to cancel bet");

        // Terminate their bet (only if the payment succeeds)
        session.winlineCount ^= WINLINE_SESSION_FLAG;
    }

    function fulfillRandomness(uint256 id, uint256 randomness) internal override nonReentrant() {
        // Get the User session associated with this request ID
        Session storage session = sessions[id];

        // Ensure we're only processing the user's currently active bet, signifying they haven't
        // modified or cancelled the bet whilst we were waiting on the VRF Callback
        require(session.winlineCount & WINLINE_SESSION_FLAG == WINLINE_SESSION_FLAG, "User Session has already been resolved");

        uint256 board = Board.generate(randomness, params.boardSize, params.symbolCount, params.payoutConstant);
        uint256 payoutWad = 0;

        // Add a third of the users bet to the jackpot. betWad cannot be less than
        // 1000000 Gwei, so the 'unchecked' (solidity 0.8, hah) multiplication into
        // division will be fine here
        jackpotWad += (session.betWad * (session.winlineCount & WINLINE_COUNT_MASK)) / 3;
        
        // Get winlineCount with the mask to omit the the session lock bit
        for (uint256 i = 0; i < (session.winlineCount & WINLINE_COUNT_MASK); i++) {
            (uint256 symbol, uint256 count) = checkWinline(
                board,
                Winline.parseWinline(session.winlines, i, params.rowSize)
            );
            // If we have 1/2 of the symbols matched
            if (count > params.rowSize / 2) {
                // If the symbol is a jackpot symbol, and we rolled a jackpot:
                if (symbol == params.symbolCount && ((randomness >> 2 * (i % 16)) + i) % 32 > 28) {
                    // This add is fine re: overflows, as jackpot is set to 0 immediately after
                    payoutWad += jackpotWad;
                    jackpotWad = 0;
                }
                // We do Symbol + 1, as the symbol is from 0-6.
                // The Symbols apply a flat multiplier: the higher the symbol value,
                // the rarer the symbol and the higher the payout multiplier.
                // We do count - 2 for these calculations, as we want to emulate the following:
                // 3 symbols: 1x multiplier
                // 4 symbols: 2x multiplier
                // 5 symbols: 3x multiplier
                payoutWad += session.betWad * ((symbol + 1) * (count - (params.rowSize / 2)));
            }
        }

        // Attempt to pay the user, revert if the payment failed
        // Again, we're protected against reentrancy
        if (payoutWad > 0) {
            (bool sentPayout, ) = session.user.call{value: payoutWad}("");
            require(sentPayout, "Failed to payout win");
        }

        // Resolve the users session, meaning they can no longer cancel the bet
        session.winlineCount ^= WINLINE_SESSION_FLAG;
        emit BetFulfilled(session.user, board, jackpotWad);
    }

    function checkWinline(uint256 board, uint256 winline) internal view returns(uint256, uint256) {
        // Array to store our slot symbols. Each index corresponds
        // to a symbol, with the value inside being the count (using an array as
        // a pseudo-sequential map structure)
        uint8[] memory results = new uint8[](params.symbolCount + 1);

        // Each winline should be the size of each row * 2 (2 bytes per slot it represents)
        for (uint256 i = 0; i < params.rowSize; i++) {
            results[getFromBoard(board, Winline.lineNibbleToRow((winline >> 2 * i) & 3), i)] += 1;
        }
 
        // Check through our results from top to bottom.
        // We do j > 1 here to save an extra iteration,
        // as we return results[0] as a short circuit at the end/bottom
        for (uint256 j = params.symbolCount; j > 1; --j) {
            if (results[j] > 2) return (j, results[j]);
        }

        // No matches, default to symbol 0
        return (0, results[0]); // Symbol 0
    }

    function getFromBoard(uint256 board, uint256 row, uint256 index) internal view returns (uint256 out) {
        out = Board.getWithRow(board, row, index, params.rowSize);
        require(out <= params.symbolCount, "Invalid symbol parsed from board for this contract");
    }

    function countWinlines(uint256 winlines) internal view returns (uint256 count) {
        uint256 bloom = 0;

        while(winlines & 3 != 0) {
            bytes32 entry = bytes32(Winline.parseWinline(winlines, 0, params.rowSize));
            bloom = Bloom.insertChecked(bloom, entry);
            winlines = winlines >> (params.rowSize * 2);
            count += 1;
        }
    }
}