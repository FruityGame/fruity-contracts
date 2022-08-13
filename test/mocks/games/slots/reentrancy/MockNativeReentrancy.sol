// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "test/mocks/games/slots/reentrancy/MockNativeIntegration.sol";

// Contract that attemps to withdraw its bet during the payout
contract MockNativeCancelReentrancy  {
    uint256 betId = 0;
    // Ensure we only run once, to prevent any other
    // unknown interactions interfering with the purpose of the test
    bool ran = false;

    function setBetId(uint256 _betId) public {
        betId = _betId;
    }

    receive() external payable {
        if (!ran) {
            ran = true;
            MockNativeIntegration(msg.sender).cancelBet(betId);
        }
    }

    fallback() external payable {
        if (!ran) {
            ran = true;
            MockNativeIntegration(msg.sender).cancelBet(betId);
        }
    }
}