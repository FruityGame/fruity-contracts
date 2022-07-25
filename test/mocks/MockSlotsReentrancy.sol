// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/BasicVideoSlots.sol";

// Contract that attemps to withdraw its bet during the payout
contract MockSlotsReentrancy {
    receive() external payable {
        BasicVideoSlots(msg.sender).withdrawBet();
    }

    fallback() external payable {
        BasicVideoSlots(msg.sender).withdrawBet();
    }
}