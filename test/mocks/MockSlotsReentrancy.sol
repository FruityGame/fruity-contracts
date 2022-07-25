// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/BasicVideoSlots.sol";

// Contract that attemps to withdraw its bet during the payout
contract MockSlotsWithdrawReentrancy {
    // Called ensures this contract only calls withdrawBet once.
    // Otherwise the call to pay the malicious contract in withdrawBet
    // could trigger the reentrancy guard and cause the test to pass, even
    // though the call to withdrawBet did succeed
    bool private called = false;

    receive() external payable {
        if (!called) {
            BasicVideoSlots(msg.sender).withdrawBet();
            called = true;
        }
    }

    fallback() external payable {
        if (!called) {
            BasicVideoSlots(msg.sender).withdrawBet();
            called = true;
        }
    }
}

contract MockSlotsWithdrawBetReentrancy {
    // Called ensures this contract only calls withdrawBet once.
    // Otherwise the call to pay the malicious contract in withdrawBet
    // could trigger the reentrancy guard and cause the test to pass, even
    // though the call to withdrawBet did succeed
    bool private called = false;

    receive() external payable {
        if (!called) {
            BasicVideoSlots(msg.sender).placeBet{value: 1 * (10 ** 9)}(1 * (10 ** 9), 1023);
            called = true;
        }
    }

    fallback() external payable {
        if (!called) {
            BasicVideoSlots(msg.sender).placeBet{value: 1 * (10 ** 9)}(1 * (10 ** 9), 1023);
            called = true;
        }
    }
}