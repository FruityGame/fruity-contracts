// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/slots/jackpot/proxy/MockExternalJackpotResolver.sol";
import "test/mocks/slots/jackpot/proxy/MockProxyJackpotResolver.sol";

contract ProxyJackpotResolverTest is Test {
    MockExternalJackpotResolver jackpotResolverExternal;
    MockProxyJackpotResolver jackpotResolver;

    uint256 constant MAX_JACKPOT = 10e18;
    uint8 constant JACKPOT_ROLE = 1;

    event JackpotChanged(uint256 oldValue, uint256 newValue);

    function setUp() public virtual {
        jackpotResolverExternal = new MockExternalJackpotResolver(MAX_JACKPOT);
        jackpotResolver = new MockProxyJackpotResolver(jackpotResolverExternal);
    }

    function testCallGetJackpot() public {
        assertEq(jackpotResolverExternal.getJackpot(), 0);
        assertEq(jackpotResolver.getJackpot(), 0);

        // Ensure anyone can call the function
        vm.prank(address(0xDEADBEEF));
        jackpotResolver.getJackpot();

        // Deposit funds into the external contract
        jackpotResolverExternal.addToJackpotExternal(1e18);

        // Ensure the proxy and external contract both report the same balance
        assertEq(jackpotResolverExternal.getJackpot(), 1e18);
        assertEq(jackpotResolver.getJackpot(), 1e18);
    }

    function testCallAddToJackpot() public {
        vm.expectRevert("UNAUTHORIZED");
        jackpotResolver._addToJackpotExternal(1e18, 0);

        // Ensure balances haven't been changed
        assertEq(jackpotResolverExternal.getJackpot(), 0);
        assertEq(jackpotResolver.getJackpot(), 0);

        // Setup the Jackpot Provider role
        jackpotResolverExternal.setRoleCapability(
            JACKPOT_ROLE,
            address(jackpotResolverExternal),
            ExternalJackpotResolver.addToJackpotExternal.selector,
            true
        );

        // Set the previously unauthorized contract to have the Jackpot Provider role
        jackpotResolverExternal.setUserRole(address(jackpotResolver), JACKPOT_ROLE, true);

        // Add jackpot now we're authorized
        jackpotResolver._addToJackpotExternal(1e18, 0);

        // Ensure balances reflect the deposit and are the same
        assertEq(jackpotResolverExternal.getJackpot(), 1e18);
        assertEq(jackpotResolver.getJackpot(), 1e18);

        // Attempt to add a value beyond the max value
        jackpotResolver._addToJackpotExternal(MAX_JACKPOT * 2, 0);

        // Ensure balances are capped at the maximum and are the same
        assertEq(jackpotResolverExternal.getJackpot(), MAX_JACKPOT);
        assertEq(jackpotResolver.getJackpot(), MAX_JACKPOT);
    }

    function testCallConsumeJackpot() public {
        jackpotResolverExternal.addToJackpotExternal(1e18);

        vm.expectRevert("UNAUTHORIZED");
        jackpotResolver._consumeJackpotExternal();

        // Ensure balances haven't been changed
        assertEq(jackpotResolverExternal.getJackpot(), 1e18);
        assertEq(jackpotResolver.getJackpot(), 1e18);

        // Setup the Jackpot Provider role
        jackpotResolverExternal.setRoleCapability(
            JACKPOT_ROLE,
            address(jackpotResolverExternal),
            ExternalJackpotResolver.consumeJackpotExternal.selector,
            true
        );

        // Set the previously unauthorized contract to have the Jackpot Provider role
        jackpotResolverExternal.setUserRole(address(jackpotResolver), JACKPOT_ROLE, true);

        // Ensure we're returned the jackpot now we have perms
        assertEq(jackpotResolver._consumeJackpotExternal(), 1e18);

        // Ensure balances are empty and are the same
        assertEq(jackpotResolverExternal.getJackpot(), 0);
        assertEq(jackpotResolver.getJackpot(), 0);
    }
}