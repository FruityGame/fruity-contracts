// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Board.sol";

contract BoardTest is Test {
    uint256 constant internal MAX_INT = 2**256 - 1;

    function setUp() public virtual {}

    function testSetup() public {
        // Expected board outcome:
        // 2:[0001|0001|0001|0000|0001] 1:[0010|0011|0100|0011|0011] 0:[0001|0000|0100|0011|0000]
        uint256 layout = Board.generate(MAX_INT);

        // Check Row 0
        assertEq(Board.get(layout, 0, 0), 0);
        assertEq(Board.get(layout, 0, 1), 3);
        assertEq(Board.get(layout, 0, 2), 4);
        assertEq(Board.get(layout, 0, 3), 0);
        assertEq(Board.get(layout, 0, 4), 1);

        // Check Row 1
        assertEq(Board.get(layout, 1, 0), 3);
        assertEq(Board.get(layout, 1, 1), 3);
        assertEq(Board.get(layout, 1, 2), 4);
        assertEq(Board.get(layout, 1, 3), 3);
        assertEq(Board.get(layout, 1, 4), 2);

        // Check Row 2
        assertEq(Board.get(layout, 2, 0), 1);
        assertEq(Board.get(layout, 2, 1), 0);
        assertEq(Board.get(layout, 2, 2), 1);
        assertEq(Board.get(layout, 2, 3), 1);
        assertEq(Board.get(layout, 2, 4), 1);
    }

    function testGetOutOfBoundsIndex() public {
        uint256 layout = Board.generate(MAX_INT);

        vm.expectRevert("Index provided for query is out of bounds");
        Board.get(layout, 0, 5);
    }

    function testGetOutOfBoundsRow() public {
        uint256 layout = Board.generate(MAX_INT);

        vm.expectRevert("Row provided for query is out of bounds");
        Board.get(layout, 3, 0);
    }
}
