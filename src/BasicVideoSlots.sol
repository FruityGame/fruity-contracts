// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "src/libraries/Winline.sol";
import "src/libraries/Board.sol";
import "src/randomness/consumer/Chainlink.sol";

// A 'Session' is a potentially active user request,
// containing their address, bet, and winlines. To
// be used in the VRF callback
struct Session {
    address user;
    uint256 betWad;
    uint256 winlines;
}

uint256 constant WINLINE_SESSION_FLAG = 1 << 255;

contract BasicVideoSlots is RandomnessConsumer, ReentrancyGuard {
    uint256 public jackpotWad = 0;

    // Mapping of chainlink RequestId's to User Sessions
    mapping(uint256 => Session) private sessions;

    event BetPlaced(address user, uint256 betId);
    event BetFulfilled(address user, uint256 board, uint256 jackpotWad);

    constructor(
        address coordinator,
        address link,
        bytes32 keyHash,
        uint64 subscriptionId
    ) RandomnessConsumer(
        coordinator,
        link,
        keyHash,
        subscriptionId
    ) {}

    modifier isValidBet(uint256 betWad) {
        require(betWad >= 1000000000000000, "Bet must be at least 1000000 Gwei");
        _;
    }

    function placeBet(uint256 betWad, uint256 winlines) public payable isValidBet(betWad) returns (uint256) {
        // Each winline applies a flat multiplier to the cost of the bet
        uint256 totalBet = betWad * Winline.count(winlines);
        require(msg.value >= totalBet, "Amount provided not enough to cover bet");

        // Initiate a new VRF Request for the user
        uint256 requestId = requestRandomness();
        // Setup the 'request fulfilled' flag on the end of the winline
        // (max # of winlines is 10*25 bits, or 250, therefore last 6 bits are fair game)
        // Inverting the lock logic means the user cannot accidentally pass in a winline with
        // the lock bit already set, meaning they could potentially get eth locked in the contract
        winlines |= WINLINE_SESSION_FLAG;
        // Create a new User session associated with the VRF RequestId for the user
        // directly using requests[msg.sender] is fine for gas as we just accessed it above
        sessions[requestId] = Session(msg.sender, betWad, winlines);
        emit BetPlaced(msg.sender, requestId);
        return requestId;
    }

    // Jackpot is only calculated and changed if the vrf fulfillment succeeds,
    // therefore we don't need to change its value in accordance with cancelling the bet
    function cancelBet(uint256 requestId) public nonReentrant() {
        // Get the currently active session for the sender
        Session storage session = sessions[requestId];
        // Ensure the session has not already been resolved/consumed
        require(session.winlines & WINLINE_SESSION_FLAG == WINLINE_SESSION_FLAG, "Cannot cancel already fulfilled bet");
        // Ensure the user is the owner of the Session
        require(session.user == msg.sender, "Invalid session requested for user");
        // All methods of this contract are protected from reentrancy, therefore
        // changing requests AFTER the call to transfer the funds is okay
        (bool success, ) = session.user.call{
            value: session.betWad * Winline.count(session.winlines)
        } ("");
        require(success, "Failed to cancel bet");

        // Terminate their bet (only if the payment succeeds)
        session.winlines ^= WINLINE_SESSION_FLAG;
    }

    function fulfillRandomness(uint256 id, uint256 randomness) internal override nonReentrant() {
        // Get the User session associated with this request ID
        Session storage session = sessions[id];

        // Ensure we're only processing the user's currently active bet, signifying they haven't
        // modified or cancelled the bet whilst we were waiting on the VRF Callback
        require(session.winlines & WINLINE_SESSION_FLAG == WINLINE_SESSION_FLAG, "User Session has already been resolved");

        uint256 board = Board.generate(randomness);
        uint256 winlineCount = Winline.count(session.winlines);
        uint256 payoutWad = 0;

        // Add a third of the users bet to the jackpot. betWad cannot be less than
        // 1000000 Gwei, so the 'unchecked' (solidity 0.8, hah) multiplication into
        // division will be fine here
        jackpotWad += (session.betWad * winlineCount) / 3;

        for (uint256 i = 0; i < winlineCount; i++) {
            (uint256 symbol, uint256 count) = checkWinline(board, Winline.parseWinline(session.winlines, i));
            // If we have 3 or more symbols matched
            if (count > 2) {
                // If the symbol is a 6 (or jackpot symbol, pick your poison) and
                // we rolled a jackpot:
                if (symbol == 6 && (randomness >> i % 16) % 32 > 28) {
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
                payoutWad += session.betWad * ((symbol + 1) * (count - 2));
            }
        }

        // Attempt to pay the user, revert if the payment failed
        // Again, we're protected against reentrancy
        if (payoutWad > 0) {
            (bool sentPayout, ) = session.user.call{value: payoutWad}("");
            require(sentPayout, "Failed to payout win");
        }

        // Resolve the users session, meaning they can no longer cancel the bet
        session.winlines ^= WINLINE_SESSION_FLAG;
        emit BetFulfilled(session.user, board, jackpotWad);
    }

    function checkWinline(uint256 board, uint256 winline) internal pure returns(uint256, uint256) {
        // Array to store our 7 slot symbols (from 0-6). Each index corresponds
        // to a symbol, with the value inside being the count (using an array as
        // a pseudo-sequential map structure)
        uint8[7] memory results = [0, 0, 0, 0, 0, 0, 0];

        results[getFromBoard(board, Winline.lineNibbleToRow((winline >> 8) & 3), 4)] += 1; // [01]010101010
        results[getFromBoard(board, Winline.lineNibbleToRow((winline >> 6) & 3), 3)] += 1; // 01[01]0101010
        results[getFromBoard(board, Winline.lineNibbleToRow((winline >> 4) & 3), 2)] += 1; // 01010[10]1010
        results[getFromBoard(board, Winline.lineNibbleToRow((winline >> 2) & 3), 1)] += 1; // 0101010[10]10
        results[getFromBoard(board, Winline.lineNibbleToRow(winline & 3), 0)] += 1; // 01010101[01]

        if (results[6] > 2) return (6, results[6]); // Symbol 6
        if (results[5] > 2) return (5, results[5]); // Symbol 5
        if (results[4] > 2) return (4, results[4]); // Symbol 4
        if (results[3] > 2) return (3, results[3]); // Symbol 3
        if (results[2] > 2) return (2, results[2]); // Symbol 2
        if (results[1] > 2) return (1, results[1]); // Symbol 1
        return (0, results[0]); // Symbol 0
    }

    function getFromBoard(uint256 board, uint256 row, uint256 index) internal pure returns (uint256 out) {
        out = Board.get(board, row, index);
        require(out < 7, "Invalid symbol parsed from board for this contract");
    }
}