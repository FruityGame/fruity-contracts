// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/payment/MockNativePaymentProcessor.sol";
import "src/payment/PaymentProcessor.sol";

contract SlotsTest is Test {
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
        assertEq(paymentProcessor.preDepositCalls(), 1);
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
        assertEq(paymentProcessor.preDepositCalls(), 0);
    }

    function testWithdraw() public {
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(address(this).balance, FUNDS + 1e18);
        assertEq(address(paymentProcessor).balance, FUNDS - 1e18);
        assertEq(paymentProcessor.preWithdrawCalls(), 1);
    }

    function testWithdrawInsufficientFunds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                paymentProcessor.balanceExternal() - (20 * 1e18),
                FUNDS
            )
        );
        paymentProcessor.withdrawExternal(address(this), FUNDS);

        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, FUNDS);
        assertEq(paymentProcessor.preWithdrawCalls(), 0);
    }
}