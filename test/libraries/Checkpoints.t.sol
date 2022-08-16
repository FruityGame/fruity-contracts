// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";

contract CheckpointsTest is Test {
    using Checkpoints for Checkpoints.History;

    mapping(address => Checkpoints.History) checkpoints;

    function setUp() public virtual {}

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function pushAtBlock(uint256 blockNumber, Checkpoints.History storage history, uint224 value) internal
    returns (uint256 oldValue, uint256 newValue) {
        vm.roll(blockNumber);
        (oldValue, newValue) = history.push(value);
    }

    function getAtNextBlock(uint256 blockNumber, Checkpoints.History storage history) internal
    returns (uint256 out) {
        vm.roll(blockNumber + 1);
        out = history.getAtBlock(blockNumber);
    }

    function testLatest() public {
        Checkpoints.History storage history = checkpoints[address(this)];

        assertEq(history.latest(), 0);
        history.push(5);
        assertEq(history.latest(), 5);
    }

    function testLatestChecked() public {
        Checkpoints.History storage history = checkpoints[address(this)];

        assertEq(history.latestChecked(), 0);
        pushAtBlock(10, history, 6);

        vm.roll(11);
        assertEq(history.latestChecked(), 6);

        vm.roll(9);
        vm.expectRevert(abi.encodeWithSelector(Checkpoints.InvalidBlockNumber.selector, 10));
        history.latestChecked();
    }

    function testPush() public {
        Checkpoints.History storage history = checkpoints[address(this)];

        (uint256 oldValue, uint256 newValue) = history.push(5);
        assertEq(oldValue, 0);
        assertEq(newValue, 5);
        assertEq(history.latest(), 5);

        (uint256 oldValue2, uint256 newValue2) = history.push(6);
        assertEq(oldValue2, 5);
        assertEq(newValue2, 6);
        assertEq(history.latest(), 6);
    }

    function testPushSearch() public {
        Checkpoints.History storage history = checkpoints[address(this)];

        pushAtBlock(1, history, 5);
        pushAtBlock(10, history, 6);

        assertEq(getAtNextBlock(1, history), 5);
        assertEq(getAtNextBlock(10, history), 6);

        vm.roll(1);
        vm.expectRevert(abi.encodeWithSelector(Checkpoints.InvalidBlockNumber.selector, 15));
        history.getAtBlock(15);
    }

    function testPushWithOps() public {
        Checkpoints.History storage history = checkpoints[address(this)];

        (uint256 oldValue, uint256 newValue) = history.push(add, 5);
        assertEq(oldValue, 0);
        assertEq(newValue, 5);
        assertEq(history.latest(), 5);

        (uint256 oldValue2, uint256 newValue2) = history.push(sub, 2);
        assertEq(oldValue2, 5);
        assertEq(newValue2, 3);
        assertEq(history.latest(), 3);
    }
}