// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "src/libraries/Winline.sol";
import "src/libraries/Board.sol";

contract WinlineTest is Test {
    // 01|01|10|10|01
    uint256 constant WINLINE_STUB = 361;

    function setUp() public virtual {}

    function constructWinline(uint256 len, uint256 rowSize) internal pure returns (uint256 out) {
        if (len == 0) return 0;

        uint256 shift = rowSize * 2;
        uint256 mask = (1 << shift) - 1;
        out = (out << shift) | (WINLINE_STUB & mask);
        for (uint256 i = 1; i < len; i++) {
            out = (out << shift) | (WINLINE_STUB & mask);
        }
    }

    // This test uses lineNibbleToRow, therefore lineNibbleToRow is also bueno if this test passes
    function testGetNibbleSingleLine() public {
        assertEq(Winline.getNibbleSingleLine(WINLINE_STUB, 0), 0);
        assertEq(Winline.getNibbleSingleLine(WINLINE_STUB, 1), 1);
        assertEq(Winline.getNibbleSingleLine(WINLINE_STUB, 2), 1);
        assertEq(Winline.getNibbleSingleLine(WINLINE_STUB, 3), 0);
        assertEq(Winline.getNibbleSingleLine(WINLINE_STUB, 4), 0);
    }

    function testLineNibbleToRowInvalidNibble() public {
        vm.expectRevert(
            abi.encodeWithSelector(Winline.InvalidWinlineNibble.selector, 0)
        );
        Winline.lineNibbleToRow(0);
    
        vm.expectRevert(
            abi.encodeWithSelector(Winline.InvalidWinlineNibble.selector, 4)
        );
        Winline.lineNibbleToRow(4);
    }

    function testGetNibbleSingleLineInvalidIndex() public {
        vm.expectRevert(
            abi.encodeWithSelector(Winline.InvalidWinlineNibble.selector, 0)
        );
        Winline.getNibbleSingleLine(WINLINE_STUB, 5);
    }

    function testGetNibbleMultiLine() public {
        // Create a winline of len 2
        uint256 winlines = (WINLINE_STUB << 10) | WINLINE_STUB;

        for (uint256 i = 0; i < 2; i++) {
            assertEq(Winline.getNibbleMultiLine(winlines, i, 0, 5), Winline.getNibbleSingleLine(WINLINE_STUB, 0));
            assertEq(Winline.getNibbleMultiLine(winlines, i, 1, 5), Winline.getNibbleSingleLine(WINLINE_STUB, 1));
            assertEq(Winline.getNibbleMultiLine(winlines, i, 2, 5), Winline.getNibbleSingleLine(WINLINE_STUB, 2));
            assertEq(Winline.getNibbleMultiLine(winlines, i, 3, 5), Winline.getNibbleSingleLine(WINLINE_STUB, 3));
            assertEq(Winline.getNibbleMultiLine(winlines, i, 4, 5), Winline.getNibbleSingleLine(WINLINE_STUB, 4));
        }
    }

    function testGetNibbleMultiLineInvalidWinlineIndex() public {
        vm.expectRevert("Invalid winline index provided");
        Winline.getNibbleMultiLine(WINLINE_STUB, 25, 0, 5);
    }

    // Will fail because nibble index 0 is less than winline len 0
    function testGetNibbleMultiLineInvalidWinlineLen() public {
        vm.expectRevert("Invalid winline nibble index provided");
        Winline.getNibbleMultiLine(WINLINE_STUB, 0, 0, 0);
    }

    function testGetNibbleMultiLineInvalidNibbleIndex() public {
        vm.expectRevert("Invalid winline nibble index provided");
        Winline.getNibbleMultiLine(WINLINE_STUB, 0, 5, 5);
    }

    function testParseWinline() public {
        assertEq(Winline.parseWinline(WINLINE_STUB, 0, 5), WINLINE_STUB);
    }

    function testParseWinlineInvalidIndex() public {
        vm.expectRevert("Invalid winline index provided");
        Winline.parseWinline(WINLINE_STUB, 25, 5);
    }

    function testParseWinlineInvalidLen() public {
        vm.expectRevert("Invalid winline length provided");
        Winline.parseWinline(WINLINE_STUB, 0, 0);
    }
}