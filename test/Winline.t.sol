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
    }

    function testParseWinline() public {
        assertEq(Winline.parseWinline(WINLINE_STUB, 0), WINLINE_STUB);
    }

    function testParseWinlineInvalidIndex() public {
        vm.expectRevert("Invalid index provided");
        Winline.parseWinline(WINLINE_STUB, 25);
    }
}