// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "test/mocks/games/slots/jackpot/proxy/MockExternalJackpotResolver.sol";

contract ExternalJackpotResolverTest is Test {
    MockExternalJackpotResolver jackpotResolver;

    uint256 constant MAX_JACKPOT = 10e18;
    uint8 constant JACKPOT_ROLE = 1;

    function setUp() public virtual {
        jackpotResolver = new MockExternalJackpotResolver(MAX_JACKPOT);
    }

    function testAddToJackpotExternalPermissions() public {
        jackpotResolver.addToJackpotExternal(1e18);
        assertEq(jackpotResolver.getJackpot(), 1e18);

        // Attempt to add externally from an unauthorized account
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xDEADBEEF));
        jackpotResolver.addToJackpotExternal(1e18);
    
        // Ensure balance hasn't changed
        assertEq(jackpotResolver.getJackpot(), 1e18);

        // Setup the Jackpot Provider role
        jackpotResolver.setRoleCapability(
            JACKPOT_ROLE,
            address(jackpotResolver),
            ExternalJackpotResolver.addToJackpotExternal.selector,
            true
        );

        // Set the previously unauthorized user to have the Jackpot Provider role
        jackpotResolver.setUserRole(address(0xDEADBEEF), JACKPOT_ROLE, true);

        // Call the function now we're authorized
        vm.prank(address(0xDEADBEEF));
        jackpotResolver.addToJackpotExternal(1e18);

        // Ensure balance has incremented
        assertEq(jackpotResolver.getJackpot(), 2e18);

        // Disable our role
        jackpotResolver.setUserRole(address(0xDEADBEEF), JACKPOT_ROLE, false);

        // Attempt to deposit again with the now removed user
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xDEADBEEF));
        jackpotResolver.addToJackpotExternal(1e18);

        // Ensure balance hasn't incremented
        assertEq(jackpotResolver.getJackpot(), 2e18);
    }

    function testAddToJackpotExternalMax() public {
        jackpotResolver.addToJackpotExternal(MAX_JACKPOT);
        jackpotResolver.addToJackpotExternal(MAX_JACKPOT);

        // Ensure balance hasn't incremented beyond the max jackpot threshold
        assertEq(jackpotResolver.getJackpot(), MAX_JACKPOT);
    }

    function testConsumeJackpotExternalPermissions() public {
        jackpotResolver.addToJackpotExternal(1e18);

        // Attempt to add externally from an unauthorized account
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xDEADBEEF));
        jackpotResolver.consumeJackpotExternal();

        // Ensure balance hasn't changed
        assertEq(jackpotResolver.getJackpot(), 1e18);

        // Consume from an authorized account
        assertEq(jackpotResolver.consumeJackpotExternal(), 1e18);

        // Ensure balance has been consumed
        assertEq(jackpotResolver.getJackpot(), 0);
    }
}