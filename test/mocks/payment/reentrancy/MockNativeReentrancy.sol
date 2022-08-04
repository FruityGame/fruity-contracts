// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "test/mocks/payment/MockNativePaymentProcessor.sol";

contract WithdrawReentrancy {
    // Only run once, because we want to ensure that we can specifically test for an
    // invariant in which the balance is not withdrawn from the contract before we reenter
    bool ran = false;
    receive() external payable {
        if (!ran) {
            ran = true;
            MockNativePaymentProcessor(msg.sender).withdrawExternal(address(this), 1e18);
        }
    }

    fallback() external payable {
        if (!ran) {
            ran = true;
            MockNativePaymentProcessor(msg.sender).withdrawExternal(address(this), 1e18);
        }
    }
}