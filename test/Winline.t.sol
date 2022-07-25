// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Winline.sol";

contract WinlineTest is Test {
    // 01|01|10|10|01
    uint256 constant WINLINE_STUB = 361;
    uint256 constant internal MAX_INT = 2**256 - 1;

    function setUp() public virtual {}

    function constructWinline(uint256 len) internal pure returns (uint256 out) {
        if (len == 0) return 0;

        out = (out << 10) | WINLINE_STUB;
        for (uint256 i = 1; i < len; i++) {
            out = (out << 10) | WINLINE_STUB;
        }
    }

    function testCount() public {
        for(uint256 i = 0; i <= 25; i++) {
            assertEq(Winline.count(constructWinline(i)), i);
        }
    }

    function testParseWinline() public {
        // 2:[0001|0001|0001|0000|0001] 1:[0010|0011|0100|0011|0011] 0:[0001|0000|0100|0011|0000]
        uint256 board = Board.generate(MAX_INT);
        // 01|01|10|10|01
        // [row 0, index 4], [row 0, index 3], [row 1, index 2] [row 1, index 1] [row 0, index 0]
        (uint256 symbol1, uint256 count1) = Winline.check(board, WINLINE_STUB, 0);
        assertEq(symbol1, 0);
        assertEq(count1, 2);

        // 1023 = 11|11|11|11|11
        (uint256 symbol2, uint256 count2) = Winline.check(board, 1023, 0);
        assertEq(symbol2, 1);
        assertEq(count2, 4);
    }

    function testParseWinlineInvalid() public {
        vm.expectRevert("Invalid winline provided");
        Winline.check(0, 0, 0);
    }

    function testParseWinlineInvalidIndex() public {
        vm.expectRevert("Invalid index provided");
        Winline.check(0, WINLINE_STUB, 25);
    }

    function testParseWinlineInvalidBoard() public {
        vm.expectRevert("Invalid number parsed from board for this Winline library");
        Winline.check(MAX_INT, WINLINE_STUB, 0);
    }
}