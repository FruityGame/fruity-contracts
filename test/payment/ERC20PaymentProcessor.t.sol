// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/MockERC20.sol";
import "test/mocks/payment/MockERC20PaymentProcessor.sol";

contract ERC20PaymentProcessorTest is Test {
    uint256 constant FUNDS = 100 * 1e18;

    MockERC20 token;
    MockERC20PaymentProcessor paymentProcessor;

    function setUp() public virtual {
        token = new MockERC20(FUNDS * 2);
        paymentProcessor = new MockERC20PaymentProcessor(address(token));

        token.transfer(address(paymentProcessor), FUNDS);
    }

    function testDeposit() public {
        token.approve(address(paymentProcessor), 1e18);
        paymentProcessor.depositExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS - 1e18);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS + 1e18);
        assertEq(paymentProcessor.balanceExternal(), FUNDS + 1e18);
    }

    function testDepositInvalidAllowance() public {
        token.approve(address(paymentProcessor), 1e17);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20PaymentProcessor.AllowanceError.selector, address(this), 1e17, 1e18)
        );
        paymentProcessor.depositExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS);
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }

    function testDepositWithMessageValue() public {
        token.approve(address(paymentProcessor), 1e18);

        vm.expectRevert("Contract doesn't accept the native token");
        paymentProcessor.depositExternal{value: 1}(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS);
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }

    function testDepositUserCannotAfford() public {
        token.approve(address(paymentProcessor), 1e18);
        token.transfer(address(0), FUNDS);

        vm.expectRevert(
            abi.encodeWithSelector(PaymentProcessor.InsufficientFunds.selector, address(this), 0, 1e18)
        );
        paymentProcessor.depositExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS);
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }

    // This prevents an invariant whereby a machine is accepting invalid bets
    function testDepositZero() public {
        token.approve(address(paymentProcessor), 1e18);

        vm.expectRevert("Deposit must be greater than zero");
        paymentProcessor.depositExternal(address(this), 0);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS);
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }

    function testWithdraw() public {
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS + 1e18);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS - 1e18);
        assertEq(paymentProcessor.balanceExternal(), FUNDS - 1e18);
    }

    function testWithdrawCannotAfford() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                FUNDS - JACKPOT_RESERVATION,
                FUNDS
            )
        );
        paymentProcessor.withdrawExternal(address(this), FUNDS);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS);
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }

    function testWithdrawZero() public {
        paymentProcessor.withdrawExternal(address(this), 0);

        // Ensure balances haven't changed
        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), FUNDS);
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }
}