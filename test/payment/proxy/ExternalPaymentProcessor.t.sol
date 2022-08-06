// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/payment/proxy/MockExternalPaymentProcessor.sol";

contract ExternalPaymentProcessorTest is Test {
    MockExternalPaymentProcessor paymentProcessor;

    uint8 constant PAYMENT_ROLE = 1;

    function setUp() public virtual {
        paymentProcessor = new MockExternalPaymentProcessor();
    }

    function testDepositExternalPermissions() public {
        paymentProcessor.depositExternal(address(this), 1e18);
        assertEq(paymentProcessor.balanceExternal(), 1e18);

        // Attempt to deposit externally from an unauthorized account
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xDEADBEEF));
        paymentProcessor.depositExternal(address(0xDEADBEEF), 1e18);
    
        // Setup the Payment Provider role
        paymentProcessor.setRoleCapability(
            PAYMENT_ROLE,
            address(paymentProcessor),
            ExternalPaymentProcessor.depositExternal.selector,
            true
        );

        // Set the previously unauthorized user to have the Payment Provider role
        paymentProcessor.setUserRole(address(0xDEADBEEF), PAYMENT_ROLE, true);

        // Call the function now we're authorized
        vm.prank(address(0xDEADBEEF));
        paymentProcessor.depositExternal(address(0xDEADBEEF), 1e18);

        // Disable our role
        paymentProcessor.setUserRole(address(0xDEADBEEF), PAYMENT_ROLE, false);

        // Attempt to deposit again with the now removed user
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xDEADBEEF));
        paymentProcessor.depositExternal(address(0xDEADBEEF), 1e18);
    }

    function testWithdrawExternalPermissions() public {
        paymentProcessor.depositExternal(address(this), 1e18);
        paymentProcessor.withdrawExternal(address(this), 1e18);

        assertEq(paymentProcessor.balanceExternal(), 0);

        // Attempt to withdraw externally from an unauthorized account
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xDEADBEEF));
        paymentProcessor.withdrawExternal(address(0xDEADBEEF), 1e18);
    }

    function testBalanceExternalPermissions() public {
        assertEq(paymentProcessor.balanceExternal(), 0);

        vm.prank(address(0xDEADBEEF));
        assertEq(paymentProcessor.balanceExternal(), 0);
    }
}