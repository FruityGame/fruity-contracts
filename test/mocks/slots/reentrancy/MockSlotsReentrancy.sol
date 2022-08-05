// SPDX-License-Identifier: MIT
/*pragma solidity ^0.8;

import "src/BasicSlots.sol";

// Contract that attemps to withdraw its bet during the payout
contract MockSlotsCancelReentrancy  {
    uint256 betId = 0;

    function setBetId(uint256 _betId) public {
        betId = _betId;
    }

    receive() external payable {
        BasicSlots(msg.sender).cancelBet(betId);
    }

    fallback() external payable {
        BasicSlots(msg.sender).cancelBet(betId);
    }
}*/