// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "solmate/tokens/WETH.sol";
import "test/mocks/payment/MockNativeVaultPaymentProcessor.sol";

contract NativeVaultPaymentProcessorTest is Test {
    uint256 constant FUNDS = 100 * 1e18;

    WETH weth;
    MockNativeVaultPaymentProcessor paymentProcessor;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        weth = new WETH();
        paymentProcessor = new MockNativeVaultPaymentProcessor(
            VaultParams(address(weth), "Mock Vault", "MVT")
        );

        deal(address(this), FUNDS);
        deal(address(paymentProcessor), FUNDS);

        vm.prank(address(paymentProcessor));
        weth.deposit{value: FUNDS}();
        //weth.transfer(address(paymentProcessor), FUNDS);
    }

    function testDeposit() public {
        paymentProcessor.depositExternal{value: 1e18}(address(this), 1e18);

        assertEq(address(this).balance, FUNDS - 1e18);
        assertEq(paymentProcessor.totalAssets(), (FUNDS - JACKPOT_RESERVATION) + 1e18);
        assertEq(paymentProcessor.balanceExternal(), FUNDS + 1e18);
    }

    /*function testDepositInvalidFunds() public {
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
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }

    function testWithdraw() public {
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(address(this).balance, FUNDS + 1e18);
        assertEq(address(paymentProcessor).balance, FUNDS - 1e18);
        assertEq(paymentProcessor.balanceExternal(), FUNDS - 1e18);
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
        assertEq(paymentProcessor.balanceExternal(), FUNDS);
    }*/
}