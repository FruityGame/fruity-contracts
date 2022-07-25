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

    constructor(
        address coordinator,
        address link,
        bytes32 keyHash,
        uint64 subscriptionId,
        address _fruity
    ) RandomnessConsumer(
        coordinator,
        link,
        keyHash,
        subscriptionId,
        address(this)
    )
    {
        fruity = ERC20(_fruity);
    }

    function placeBet(uint256 bet, uint256 winlines) public {
        require(requests[msg.sender] == 0, "Cannot place bet: you already have an active bet placed");
        require(fruity.balanceOf(msg.sender) >= bet * Winline.count(winlines), "Fruity Balance not high enough to make bet");

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