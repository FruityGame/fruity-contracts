// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/BasicVideoSlots.sol";

// Contract that attemps to withdraw its bet during the payout
contract MockSlotsCancelReentrancy {
    // Called ensures this contract only calls withdrawBet once.
    // Otherwise the call to pay the malicious contract in withdrawBet
    // could trigger the reentrancy guard and cause the test to pass, even
    // though the call to withdrawBet did succeed
    bool public called = false;

    uint256 betId = 0;

    function setBetId(uint256 _betId) public {
        betId = _betId;
    }

    receive() external payable {
        if (!called) {
            BasicVideoSlots(msg.sender).cancelBet(betId);
            called = true;
        }
    }

    fallback() external payable {
        if (!called) {
            BasicVideoSlots(msg.sender).cancelBet(betId);
            called = true;
        }
    }
}