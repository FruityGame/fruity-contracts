// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "test/mocks/tokens/MockERC20.sol";
import "test/mocks/payment/MockERC20VaultPaymentProcessor.sol";

import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";

// Underlying ERC4626 impl is tested in the Solmate repo, therefore less
// tests here are done under the assumption that their unit tests are sufficient
contract ERC20VaultPaymentProcessorTest is Test {
    uint256 constant FUNDS = 100 * 1e18;

    MockERC20 token;
    MockERC20VaultPaymentProcessor paymentProcessor;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        token = new MockERC20(FUNDS);
        paymentProcessor = new MockERC20VaultPaymentProcessor(
            ERC20VaultPaymentProcessor.VaultParams(token, "Mock Vault", "MVT")
        );

        token.approve(address(paymentProcessor), 2e18);
    }

    function checkERC4626Invariants() internal {
        // Ensure no ERC4626 shares have been accredited
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure ERC4626 total supply has not changed
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testDeposit() public {
        token.approve(address(paymentProcessor), 1e18);
        paymentProcessor.depositExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS - 1e18);
        assertEq(token.balanceOf(address(paymentProcessor)), 1e18);
        assertEq(paymentProcessor.totalAssets(), 1e18);
        assertEq(paymentProcessor._balance(), 1e18);

        checkERC4626Invariants();
    }

    function testDepositInvalidAllowance() public {
        token.approve(address(paymentProcessor), 1e17);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20PaymentProcessor.AllowanceError.selector, address(this), 1e17, 1e18)
        );
        paymentProcessor.depositExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        checkERC4626Invariants();
    }

    function testDepositWithMessageValue() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20PaymentProcessor.MsgValueNotAllowed.selector));
        paymentProcessor.depositExternal{value: 1}(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        checkERC4626Invariants();
    }

    function testDepositUserCannotAfford() public {
        token.approve(address(paymentProcessor), 1e18);
        token.transfer(address(0), FUNDS);

        vm.expectRevert(
            abi.encodeWithSelector(PaymentProcessor.InsufficientFunds.selector, address(this), 0, 1e18)
        );
        paymentProcessor.depositExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(paymentProcessor)), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        checkERC4626Invariants();
    }

    function testWithdraw() public {
        token.mintExternal(address(paymentProcessor), 1e18);
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS + 1e18);
        assertEq(token.balanceOf(address(paymentProcessor)), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        checkERC4626Invariants();
    }

    function testWithdrawCannotAfford() public {
        token.mintExternal(address(paymentProcessor), 1e17);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                1e17,
                1e18
            )
        );
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(token.balanceOf(address(this)), FUNDS);
        assertEq(token.balanceOf(address(paymentProcessor)), 1e17);
        assertEq(paymentProcessor.totalAssets(), 1e17);
        assertEq(paymentProcessor._balance(), 1e17);

        checkERC4626Invariants();
    }

    // Test synergy with the ERC4626 deposit and the PaymentProcessor _deposit() methods
    function testVaultYieldAsymmetricalShares() public {
        address us = address(this);
        address them = address(0xDEADBEEF);
        address paymentContract = address(paymentProcessor);

        // (us) Deposit 2 'Token'
        token.approve(paymentContract, 2e18);
        uint256 ourShares = paymentProcessor.deposit(2e18, us);

        // (them) Deposit 1 'Token'
        token.mintExternal(them, 1e18);
        vm.prank(them);
        token.approve(paymentContract, 1e18);
        vm.prank(them);
        uint256 theirShares = paymentProcessor.deposit(1e18, them);

        // Yield accumulation of 1000 'Token' via _deposit()
        token.mintExternal(address(0), 1000e18);
        vm.prank(address(0));
        token.approve(paymentContract, 1000e18);
        vm.prank(address(0));
        paymentProcessor.depositExternal(address(0), 1000e18);

        // 1000 Token + (us) 2 Token + (them) 1 Token
        assertEq(token.balanceOf(paymentContract), 1003e18);
        assertEq(paymentProcessor.totalAssets(), 1003e18);
        assertEq(paymentProcessor._balance(), 1003e18);

        // Ensure our total share supply isn't factoring in the external _deposit()
        assertEq(paymentProcessor.totalSupply(), 3e18);

        // 1/3 of the new deposit value
        uint256 third = uint256(1000e18) / uint256(3);
        // Ensure that our shares are now worth more as a result of the non-ERC4626 deposit
        assert(paymentProcessor.previewWithdraw(2e18) < ourShares);
        assert(paymentProcessor.previewWithdraw(1e18) < theirShares);
        assertEq(paymentProcessor.previewWithdraw(2e18 + (third * 2)), ourShares);
        assertEq(paymentProcessor.previewWithdraw(1e18 + third), theirShares);
        assertEq(paymentProcessor.previewRedeem(ourShares), 2e18 + (third * 2));
        assertEq(paymentProcessor.previewRedeem(theirShares), 1e18 + third);

        paymentProcessor.redeem(ourShares, us, us);
        vm.prank(them);
        paymentProcessor.redeem(theirShares, them, them);

        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(us), 0);
        assertEq(paymentProcessor.balanceOf(them), 0);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure funds have been received with Yield
        assertEq(token.balanceOf(us), FUNDS + (third * 2)); // We should receive 66%
        // Accomodate the roundup in the previewRedeem()
        assertEq(token.balanceOf(them), 1e18 + third + 1); // They should receive 33%
        assertEq(token.balanceOf(paymentContract), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        // Ensure all shares have been redeemed
        assertEq(paymentProcessor.totalSupply(), 0);
    }
}