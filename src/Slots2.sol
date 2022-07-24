// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "src/libraries/Winline.sol";
import "src/libraries/Board.sol";
import "src/randomness/consumer/Chainlink.sol";

struct Session {
    address user;
    uint256 winlines;
}

contract BasicVideoSlots is RandomnessConsumer {
    ERC20 internal fruity;

    // Mapping of user addresses to chainlink requestId's
    mapping(address => uint256) requests;
    // Mapping of chainlink requestId's to Winlines
    mapping(uint256 => Session) sessions;

    constructor(uint64 _subscriptionId) RandomnessConsumer(
        0x6A2AAd07396B36Fe02a22b33cf443582f682c82f,
        0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06,
        0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314,
        _subscriptionId,
        address(this)
    ) {}

    function placeBet(uint256 bet, uint256 winlines) public {
        require(requests[msg.sender] == 0, "Cannot place bet: you already have an active bet placed");
        require(fruity.balanceOf(msg.sender) >= (bet * Winline.count(winlines)), "Fruity Balance not high enough to make bet.");

        requests[msg.sender] = requestRandomness();
        sessions[requests[msg.sender]] = Session(msg.sender, winlines);
    }

    function fulfillRandomness(uint256 id, uint256 randomness) internal override {
        Session memory session = sessions[id];
        require(requests[session.user] != 0, "Invariant detected: No request present for user");
        uint256 board = Board.generate(randomness);
        
        for (uint256 i = 0; i < Winline.count(session.winlines); i++) {

        }
    }
}