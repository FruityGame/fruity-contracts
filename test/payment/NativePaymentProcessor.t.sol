// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "test/mocks/payment/MockNativePaymentProcessor.sol";
import "test/mocks/payment/reentrancy/MockNativeReentrancy.sol";

import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";

contract NativePaymentProcessorTest is Test {
    uint256 constant FUNDS = 100 * 1e18;

    MockNativePaymentProcessor paymentProcessor;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        paymentProcessor = new MockNativePaymentProcessor();

        deal(address(this), FUNDS);
        deal(address(paymentProcessor), FUNDS);
    }

    function testDeposit() public {
        paymentProcessor.depositExternal{value: 1e18}(address(this), 1e18);

        assertEq(address(this).balance, FUNDS - 1e18);
        assertEq(address(paymentProcessor).balance, FUNDS + 1e18);
        assertEq(paymentProcessor._balance(), FUNDS + 1e18);
    }

    function testDepositInvalidFunds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(this),
                0,
                1e18
            )
        );
        paymentProcessor.depositExternal(address(this), 1e18);

        // Ensure no funds have been taken
        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, FUNDS);
        assertEq(paymentProcessor._balance(), FUNDS);
    }

    // This prevents an invariant whereby a machine is accepting invalid bets
    function testFailDepositZero() public {
        paymentProcessor.depositExternal(address(this), 0);
    }

    function testWithdraw() public {
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(address(this).balance, FUNDS + 1e18);
        assertEq(address(paymentProcessor).balance, FUNDS - 1e18);
        assertEq(paymentProcessor._balance(), FUNDS - 1e18);
    }

    function testWithdrawInsufficientFunds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                paymentProcessor._balance() - JACKPOT_RESERVATION,
                FUNDS
            )
        );
        paymentProcessor.withdrawExternal(address(this), FUNDS);

        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, FUNDS);
        assertEq(paymentProcessor._balance(), FUNDS);
    }

    function testWithdrawReentrancy() public {
        WithdrawReentrancy maliciousContract = new WithdrawReentrancy();

        vm.prank(address(maliciousContract));
        paymentProcessor.withdrawExternal(address(maliciousContract), 1e18);

        // Ensure state has been correctly updated (i.e. balance is deducted before the call())
        assertEq(address(maliciousContract).balance, 2e18);
        assertEq(address(paymentProcessor).balance, FUNDS - 2e18);
        assertEq(paymentProcessor._balance(), FUNDS - 2e18);
    }

    function testWithdrawZero() public {
        paymentProcessor.withdrawExternal(address(this), 0);

        // Ensure balances haven't changed
        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, FUNDS);
        assertEq(paymentProcessor._balance(), FUNDS);
    }
}