// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/payment/MockNativeVaultPaymentProcessor.sol";
import "test/mocks/payment/reentrancy/MockNativeVaultReentrancy.sol";

import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";

contract NativeVaultPaymentProcessorTest is Test {
    uint256 constant FUNDS = 100 * 1e18;

    MockNativeVaultPaymentProcessor paymentProcessor;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        paymentProcessor = new MockNativeVaultPaymentProcessor(
            NativeVaultPaymentProcessor.VaultParams("Mock Vault", "MVT")
        );

        deal(address(this), FUNDS);
    }

    function testDeposit() public {
        paymentProcessor.depositExternal{value: 1e18}(address(this), 1e18);

        assertEq(address(this).balance, FUNDS - 1e18);
        assertEq(address(paymentProcessor).balance, 1e18);
        assertEq(paymentProcessor._balance(), 1e18);
        assertEq(paymentProcessor.totalAssets(), 1e18);

        /*
            Ensure no ERC4626 accreditations have taken place
        */
        // Ensure no shares have been accredited
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply has not changed
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testDepositInsufficientFunds() public {
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
        assertEq(address(paymentProcessor).balance, 0);
        assertEq(paymentProcessor._balance(), 0);
        assertEq(paymentProcessor.totalAssets(), 0);

        /*
            Ensure no ERC4626 accreditations have taken place
        */
        // Ensure no shares have been accredited
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply has not changed (we're not using ERC4626 methods)
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testWithdraw() public {
        paymentProcessor.depositExternal{value: 1e18}(address(this), 1e18);

        // Ensure funds have been deposited
        assertEq(address(this).balance, FUNDS - 1e18);
        assertEq(address(paymentProcessor).balance, 1e18);
        assertEq(paymentProcessor.totalAssets(), 1e18);
        assertEq(paymentProcessor._balance(), 1e18);

        // Withdraw funds with _withdraw()
        paymentProcessor.withdrawExternal(address(this), 1e18);

        // Ensure funds have been accredited
        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, 0);
        assertEq(paymentProcessor._balance(), 0);
        assertEq(paymentProcessor.totalAssets(), 0);

        /*
            Ensure no ERC4626 accreditations have taken place
        */
        // Ensure no shares have been accredited
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply has not changed (we're not using ERC4626 methods)
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testWithdrawInsufficientFunds() public {
        paymentProcessor.depositExternal{value: 1e18}(address(this), 1e18);

        // Overwrite Eth value of contract
        deal(address(paymentProcessor), 1e17);

        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                1e17, // Has
                1e18 // Wanted
            )
        );
        paymentProcessor.withdrawExternal(address(this), 1e18);

        // Ensure no funds have been taken
        assertEq(address(this).balance, FUNDS - 1e18); // Earlier deposit is still there
        assertEq(address(paymentProcessor).balance, 1e17);
        assertEq(paymentProcessor._balance(), 1e17);
        assertEq(paymentProcessor.totalAssets(), 1e17);

        /*
            Ensure no ERC4626 accreditations have taken place
        */
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply has not been decreased
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testDepositWithdrawSharesSingle() public {
        uint256 shares = paymentProcessor.deposit{value: 1e18}(1e18, address(this));

        // Ensure funds have been deposited
        assertEq(address(this).balance, FUNDS - 1e18);
        assertEq(address(paymentProcessor).balance, 1e18);
        assertEq(paymentProcessor.totalAssets(), 1e18);
        assertEq(paymentProcessor._balance(), 1e18);
        assertEq(paymentProcessor.convertToAssets(shares), 1e18);
        assertEq(paymentProcessor.previewMint(shares), 1e18);
        assertEq(paymentProcessor.previewDeposit(1e18), shares);

        // Ensure shares have been accredited
        assertEq(paymentProcessor.balanceOf(address(this)), shares);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 1e18);

        // Redeem our shares
        paymentProcessor.redeem(shares, address(this), address(this));

        // Ensure funds have been deposited
        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply of shares has been decreased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testMintWithdrawSharesSingle() public {
        uint256 assets = paymentProcessor.mint{value: 1e18}(1e18, address(this));

        assertEq(assets, 1e18);

        // Ensure funds have been deposited
        assertEq(address(this).balance, FUNDS - 1e18);
        assertEq(address(paymentProcessor).balance, 1e18);
        assertEq(paymentProcessor.totalAssets(), 1e18);
        assertEq(paymentProcessor._balance(), 1e18);

        // Ensure shares have been accredited
        assertEq(paymentProcessor.balanceOf(address(this)), 1e18);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);
        assertEq(paymentProcessor.convertToShares(assets), 1e18);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 1e18);

        // Redeem our shares
        paymentProcessor.redeem(assets, address(this), address(this));

        // Ensure funds have been withdrawn
        assertEq(address(this).balance, FUNDS);
        assertEq(address(paymentProcessor).balance, 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        // Ensure shares have been redeemed
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);

        // Ensure total supply of shares has been decreased
        // proportionally to the withdrawn ether
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testMintDepositWithdrawRedeemMultiple() public {
        address us = address(this);
        address them = address(0xDEADBEEF);
        address paymentContract = address(paymentProcessor);

        uint256 ourShares = paymentProcessor.deposit{value: 1e18}(1e18, us);

        deal(them, 1e18);
        vm.prank(them);
        uint256 otherShares = paymentProcessor.deposit{value: 1e18}(1e18, them);

        // Our shares of the pot should be equal
        assertEq(ourShares, otherShares);

        // Ensure funds have been deposited
        assertEq(us.balance, FUNDS - 1e18);
        assertEq(them.balance, 0);
        assertEq(paymentContract.balance, 2e18);
        assertEq(paymentProcessor.totalAssets(), 2e18);
        assertEq(paymentProcessor._balance(), 2e18);

        // Ensure shares have been accredited
        assertEq(paymentProcessor.balanceOf(us), ourShares);
        assertEq(paymentProcessor.balanceOf(them), otherShares);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 2e18);

        // Deposit another set of shares for us
        paymentProcessor.deposit{value: 1e18}(1e18, us);

        // Ensure funds are correct
        assertEq(us.balance, FUNDS - 2e18);
        assertEq(them.balance, 0);
        assertEq(paymentContract.balance, 3e18);
        assertEq(paymentProcessor.totalAssets(), 3e18);
        assertEq(paymentProcessor._balance(), 3e18);

        // Ensure shares have been accredited
        assertEq(paymentProcessor.balanceOf(us), 2e18);
        assertEq(paymentProcessor.balanceOf(them), otherShares);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 3e18);

        // Redeem half of our shares
        paymentProcessor.redeem(ourShares, us, us);

        // Ensure funds have been deposited
        assertEq(us.balance, FUNDS - 1e18);
        assertEq(them.balance, 0);
        assertEq(paymentContract.balance, 2e18);
        assertEq(paymentProcessor.totalAssets(), 2e18);
        assertEq(paymentProcessor._balance(), 2e18);

        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(us), 1e18);
        assertEq(paymentProcessor.balanceOf(them), 1e18);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 2e18);

        // Mint 1 Eth worth of shares for our user
        paymentProcessor.mint{value: 1e18}(1e18, address(this));

        // Ensure funds have been deposited
        assertEq(us.balance, FUNDS - 2e18);
        assertEq(them.balance, 0);
        assertEq(paymentContract.balance, 3e18);
        assertEq(paymentProcessor.totalAssets(), 3e18);
        assertEq(paymentProcessor._balance(), 3e18);
    
        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(us), 2e18);
        assertEq(paymentProcessor.balanceOf(them), 1e18);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 3e18);

        // Withdraw 1 Eth worth of shares for our user
        paymentProcessor.withdraw(1e18, us, us);

        // Ensure funds have been deposited
        assertEq(us.balance, FUNDS - 1e18);
        assertEq(them.balance, 0);
        assertEq(paymentContract.balance, 2e18);
        assertEq(paymentProcessor.totalAssets(), 2e18);
        assertEq(paymentProcessor._balance(), 2e18);
    
        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(us), 1e18);
        assertEq(paymentProcessor.balanceOf(them), 1e18);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentProcessor.totalSupply(), 2e18);

        // Test yield accumulation
        deal(address(0), 1e18);
        vm.prank(address(0));
        // Deposit with _deposit()
        paymentProcessor.depositExternal{value: 1e18}(address(0), 1e18);

        // Ensure total supply of shares has been increased proportionally to
        // the deposited ether
        assertEq(paymentContract.balance, 3e18);
        assertEq(paymentProcessor.totalAssets(), 3e18);
        assertEq(paymentProcessor._balance(), 3e18);
        assertEq(paymentProcessor.totalSupply(), 2e18);

        // Withdraw our shares
        paymentProcessor.redeem(1e18, us, us);
        // Withdraw other users shares
        vm.prank(them);
        paymentProcessor.redeem(1e18, them, them);

        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(us), 0);
        assertEq(paymentProcessor.balanceOf(them), 0);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure funds have been received with Yield
        assertEq(us.balance, FUNDS + 0.5e18);
        assertEq(them.balance, 1e18 + 0.5e18);
        assertEq(paymentContract.balance, 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);
    }

    function testVaultYieldAsymmetricalShares() public {
        address us = address(this);
        address them = address(0xDEADBEEF);
        address paymentContract = address(paymentProcessor);

        uint256 ourShares = paymentProcessor.deposit{value: 2e18}(2e18, us);

        deal(them, 1e18);
        vm.prank(them);
        uint256 theirShares = paymentProcessor.deposit{value: 1e18}(1e18, them);

        // Yield accumulation
        deal(address(0), 1000e18);
        vm.prank(address(0));
        // Deposit with _deposit()
        paymentProcessor.depositExternal{value: 1000e18}(address(0), 1000e18);
        // 1/3 of the new deposit value
        uint256 third = uint256(1000e18) / uint256(3);
        // Ensure that our shares are now worth more as a result of the deposit
        // (if we were to use withdraw to take out our original deposit)
        assert(paymentProcessor.previewWithdraw(2e18) < ourShares);
        assert(paymentProcessor.previewWithdraw(1e18) < theirShares);
        assertEq(paymentProcessor.previewWithdraw(2e18 + (third * 2)), ourShares);
        assertEq(paymentProcessor.previewWithdraw(1e18 + third), theirShares);
        assertEq(paymentProcessor.previewRedeem(ourShares), 2e18 + (third * 2));
        assertEq(paymentProcessor.previewRedeem(theirShares), 1e18 + third);

        // 1000 Eth + (us) 2 Eth + (them) 1 Eth
        assertEq(paymentContract.balance, 1003e18);
        assertEq(paymentProcessor.totalAssets(), 1003e18);
        assertEq(paymentProcessor._balance(), 1003e18);

        // Ensure our total share supply isn't factoring in the external _deposit()
        assertEq(paymentProcessor.totalSupply(), 3e18);

        paymentProcessor.redeem(ourShares, us, us);
        vm.prank(them);
        paymentProcessor.redeem(theirShares, them, them);

        // Ensure shares have been taken
        assertEq(paymentProcessor.balanceOf(us), 0);
        assertEq(paymentProcessor.balanceOf(them), 0);
        assertEq(paymentProcessor.balanceOf(paymentContract), 0);

        // Ensure funds have been received with Yield
        assertEq(us.balance, FUNDS + (third * 2)); // We should receive 66%
        // Accomodate the roundup in the previewRedeem()
        assertEq(them.balance, 1e18 + third + 1); // They should receive 33%
        assertEq(paymentContract.balance, 0);
        assertEq(paymentProcessor.totalAssets(), 0);
        assertEq(paymentProcessor._balance(), 0);

        // Ensure all shares have been redeemed
        assertEq(paymentProcessor.totalSupply(), 0);
    }

    function testDepositInvalidValueProvided() public {
        vm.expectRevert("INVALID_ETH_AMOUNT");
        paymentProcessor.deposit{value: 1e17}(1e18, address(this));
    }

    function testDepositZeroValueProvided() public {
        vm.expectRevert("ZERO_SHARES");
        paymentProcessor.deposit{value: 0}(0, address(this));
    }

    function testMintInvalidValueProvided() public {
        vm.expectRevert("INVALID_ETH_AMOUNT");
        paymentProcessor.mint{value: 1e17}(1e18, address(this));
    }

    function testMintZeroValueProvided() public {
        paymentProcessor.mint{value: 0}(0, address(this));

        assertEq(address(paymentProcessor).balance, 0);
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.balanceOf(address(paymentProcessor)), 0);
        assertEq(paymentProcessor.totalSupply(), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
    }

    function testWithdrawInsufficientFundsERC4626() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                0,
                1e18
            )
        );
        paymentProcessor.withdraw(1e18, address(this), address(this));
    }

    function testWithdrawZeroERC4626() public {
        paymentProcessor.deposit{value: 1e18}(1e18, address(this));
        paymentProcessor.withdraw(0, address(this), address(this));

        assertEq(address(paymentProcessor).balance, 1e18);
        assertEq(paymentProcessor.balanceOf(address(this)), 1e18);
        assertEq(paymentProcessor.totalSupply(), 1e18);
        assertEq(paymentProcessor.totalAssets(), 1e18);

        paymentProcessor.withdraw(1e18, address(this), address(this));
        paymentProcessor.withdraw(0, address(this), address(this));

        assertEq(address(paymentProcessor).balance, 0);
        assertEq(paymentProcessor.balanceOf(address(this)), 0);
        assertEq(paymentProcessor.totalSupply(), 0);
        assertEq(paymentProcessor.totalAssets(), 0);
    }

    function testFailWithdrawMoreThanAllowed() public {
        deal(address(0xDEADBEEF), 1e18);
        vm.prank(address(0xDEADBEEF));
        paymentProcessor.deposit{value: 1e18}(1e18, address(0xDEADBEEF));

        paymentProcessor.deposit{value: 1e18 - 1}(1e18 - 1, address(this));
        paymentProcessor.withdraw(1e18, address(this), address(this));
    }

    function testRedeemInsufficientFunds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(paymentProcessor),
                0,
                1e18
            )
        );
        paymentProcessor.redeem(1e18, address(this), address(this));
    }

    function testRedeemZero() public {
        vm.expectRevert("ZERO_ASSETS");
        paymentProcessor.redeem(0, address(this), address(this));
    }

    function testFailRedeemMoreThanAllowed() public {
        deal(address(0xDEADBEEF), 1e18);
        vm.prank(address(0xDEADBEEF));
        paymentProcessor.deposit{value: 1e18}(1e18, address(0xDEADBEEF));

        paymentProcessor.deposit{value: 1e18 - 1}(1e18 - 1, address(this));
        paymentProcessor.redeem(1e18, address(this), address(this));
    }

    function testWithdrawReentrancyERC4626() public {
        WithdrawReentrancy maliciousContract = new WithdrawReentrancy();
        deal(address(maliciousContract), 10e18);

        paymentProcessor.deposit{value: 1e18}(1e18, address(this));

        vm.prank(address(maliciousContract));
        paymentProcessor.deposit{value: 10e18}(10e18, address(maliciousContract));

        assertEq(paymentProcessor.totalSupply(), 11e18);
        assertEq(paymentProcessor.totalAssets(), 11e18);
        assertEq(paymentProcessor.balanceOf(address(maliciousContract)), 10e18);
        assertEq(paymentProcessor.balanceOf(address(this)), 1e18);
        assertEq(address(maliciousContract).balance, 0);

        // Contract calls deposit() with 1Eth, then tries to withdraw twice
        vm.prank(address(maliciousContract));
        paymentProcessor.withdraw(1e18, address(maliciousContract), address(maliciousContract));

        // Ensure balances have been correctly adjusted (i.e. we're burning tokens/adjusting state)
        // before attempting to pay the user
        assertEq(paymentProcessor.totalSupply(), 9e18);
        assertEq(paymentProcessor.totalAssets(), 9e18);
        assertEq(paymentProcessor.balanceOf(address(maliciousContract)), 8e18);
        assertEq(paymentProcessor.balanceOf(address(this)), 1e18);
        assertEq(address(maliciousContract).balance, 2e18);
    }

    function testRedeemReentrancyERC4626() public {
        RedeemReentrancy maliciousContract = new RedeemReentrancy();
        deal(address(maliciousContract), 10e18);

        paymentProcessor.mint{value: 1e18}(1e18, address(this));

        vm.prank(address(maliciousContract));
        paymentProcessor.mint{value: 10e18}(10e18, address(maliciousContract));

        assertEq(paymentProcessor.totalSupply(), 11e18);
        assertEq(paymentProcessor.totalAssets(), 11e18);
        assertEq(paymentProcessor.balanceOf(address(maliciousContract)), 10e18);
        assertEq(paymentProcessor.balanceOf(address(this)), 1e18);
        assertEq(address(maliciousContract).balance, 0);

        // Contract calls mint() with 1Eth, then tries to redeem twice
        vm.prank(address(maliciousContract));
        paymentProcessor.redeem(1e18, address(maliciousContract), address(maliciousContract));

        // Ensure balances have been correctly adjusted (i.e. we're burning tokens/adjusting state)
        // before attempting to pay the user
        assertEq(paymentProcessor.totalSupply(), 9e18);
        assertEq(paymentProcessor.totalAssets(), 9e18);
        assertEq(paymentProcessor.balanceOf(address(maliciousContract)), 8e18);
        assertEq(paymentProcessor.balanceOf(address(this)), 1e18);
        assertEq(address(maliciousContract).balance, 2e18);
    }
}