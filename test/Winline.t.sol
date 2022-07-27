// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Winline.sol";
import "src/libraries/Board.sol";

contract WinlineTest is Test {
    // 01|01|10|10|01
    uint256 constant WINLINE_STUB = 361;
    uint256 constant internal MAX_INT = 2**256 - 1;

    function setUp() public virtual {}

    function constructWinline(uint256 len, uint256 rowSize) internal view returns (uint256 out) {
        if (len == 0) return 0;

        uint256 shift = rowSize * 2;
        uint256 mask = (1 << shift) - 1;
        out = (out << shift) | (WINLINE_STUB & mask);
        for (uint256 i = 1; i < len; i++) {
            out = (out << shift) | (WINLINE_STUB & mask);
        }
    }

    function testLineNibbleToRow() public {
        assertEq(Winline.lineNibbleToRow((WINLINE_STUB) & 3), 0);
        assertEq(Winline.lineNibbleToRow((WINLINE_STUB >> 2) & 3), 1);
        assertEq(Winline.lineNibbleToRow((WINLINE_STUB >> 4) & 3), 1);
        assertEq(Winline.lineNibbleToRow((WINLINE_STUB >> 6) & 3), 0);
        assertEq(Winline.lineNibbleToRow((WINLINE_STUB >> 8) & 3), 0);
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

    function testParseWinline() public {
        assertEq(Winline.parseWinline(WINLINE_STUB, 0, 5), WINLINE_STUB);
    }

    function testParseWinlineInvalidIndex() public {
        vm.expectRevert("Invalid index provided");
        Winline.parseWinline(WINLINE_STUB, 25, 5);
    }

    function testParseWinlineInvalidSize() public {
        vm.expectRevert("Invalid winline size provided");
        Winline.parseWinline(WINLINE_STUB, 0, 0);
    }
}