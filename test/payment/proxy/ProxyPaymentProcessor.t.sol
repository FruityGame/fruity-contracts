// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/payment/proxy/MockExternalPaymentProcessor.sol";
import "test/mocks/payment/proxy/MockProxyPaymentProcessor.sol";

contract ProxyPaymentProcessorTest is Test {
    MockExternalPaymentProcessor paymentProcessorExternal;
    MockProxyPaymentProcessor paymentProcessor;

    uint8 constant PAYMENT_ROLE = 1;

    function setUp() public virtual {
        paymentProcessorExternal = new MockExternalPaymentProcessor();
        paymentProcessor = new MockProxyPaymentProcessor(paymentProcessorExternal);
    }

    function testCallBalance() public {
        assertEq(paymentProcessorExternal._balance(), 0);
        assertEq(paymentProcessor._balance(), 0);

        // Ensure anyone can call the function
        vm.prank(address(0xDEADBEEF));
        paymentProcessor._balance();

        // Deposit funds into the external contract
        paymentProcessorExternal.depositExternal(address(this), 1e18);

        // Ensure the proxy and external contract both report the same balance
        assertEq(paymentProcessorExternal._balance(), 1e18);
        assertEq(paymentProcessor._balance(), 1e18);
    }

    function testCallDeposit() public {
        vm.expectRevert("UNAUTHORIZED");
        paymentProcessor._depositExternal(address(paymentProcessor), 1e18);

        // Setup the Payment Provider role
        paymentProcessorExternal.setRoleCapability(
            PAYMENT_ROLE,
            address(paymentProcessorExternal),
            ExternalPaymentProcessor.depositExternal.selector,
            true
        );

        // Set the proxy contract to have the Payment Provider role
        paymentProcessorExternal.setUserRole(address(paymentProcessor), PAYMENT_ROLE, true);

        // Attempt to deposit with the new role set
        paymentProcessor._depositExternal(address(paymentProcessor), 1e18);

        // Ensure balances are reported as the same
        assertEq(paymentProcessorExternal._balance(), 1e18);
        assertEq(paymentProcessor._balance(), 1e18);
    }

    function testCallWithdraw() public {
        paymentProcessorExternal.depositExternal(address(this), 1e18);

        vm.expectRevert("UNAUTHORIZED");
        paymentProcessor._withdrawExternal(address(paymentProcessor), 1e18);

        // Setup the Payment Provider role
        paymentProcessorExternal.setRoleCapability(
            PAYMENT_ROLE,
            address(paymentProcessorExternal),
            ExternalPaymentProcessor.withdrawExternal.selector,
            true
        );

        // Set the proxy contract to have the Payment Provider role
        paymentProcessorExternal.setUserRole(address(paymentProcessor), PAYMENT_ROLE, true);

        // Attempt to withdraw with the new role set
        paymentProcessor._withdrawExternal(address(paymentProcessor), 1e18);

        // Ensure balances are reported as the same
        assertEq(paymentProcessorExternal._balance(), 0);
        assertEq(paymentProcessor._balance(), 0);
    }
}