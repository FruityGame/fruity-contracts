// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "test/mocks/games/slots/jackpot/MockLocalJackpotResolver.sol";

contract LocalJackpotResolverTest is Test {
    MockLocalJackpotResolver jackpotResolver;

    event JackpotChanged(uint256 oldValue, uint256 newValue);

    function setUp() public virtual {
        jackpotResolver = new MockLocalJackpotResolver();
    }

    function testAddToJackpot() public {
        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(0), uint256(1e18));
        jackpotResolver._addToJackpotExternal(1e18, 20e18);

        assertEq(jackpotResolver.getJackpot(), 1e18);
    }

    function testAddToJackpotBeyondMax() public {
        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(0), uint256(20e18));
        jackpotResolver._addToJackpotExternal(25e18, 20e18);

        assertEq(jackpotResolver.getJackpot(), 20e18);

        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(20e18), uint256(20e18));
        jackpotResolver._addToJackpotExternal(1e1, 20e18);

        assertEq(jackpotResolver.getJackpot(), 20e18);
    }

    function testAddToJackpotZeroMax() public {
        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(0), uint256(0));
        jackpotResolver._addToJackpotExternal(25e18, 0);

        assertEq(jackpotResolver.getJackpot(), 0);

        jackpotResolver._addToJackpotExternal(1e18, 1e18);
        assertEq(jackpotResolver.getJackpot(), 1e18);

        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(1e18), uint256(0));
        jackpotResolver._addToJackpotExternal(1e18, 0);

        assertEq(jackpotResolver.getJackpot(), 0);
    }

    function testConsumeJackpot() public {
        jackpotResolver._addToJackpotExternal(1e18, 20e18);

        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(1e18), uint256(0));
        jackpotResolver._consumeJackpotExternal();

        assertEq(jackpotResolver.getJackpot(), 0);
    }

    function testConsumeJackpotZero() public {
        vm.expectEmit(true, false, false, true);
        emit JackpotChanged(uint256(0), uint256(0));
        jackpotResolver._consumeJackpotExternal();

        assertEq(jackpotResolver.getJackpot(), 0);
    }
}