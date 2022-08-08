// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Board.sol";
import { SlotParams } from "src/games/slots/BaseSlots.sol";

contract BoardTest is Test {
    uint256 constant internal MAX_INT = 2**256 - 1;

    function setUp() public virtual {}

    function testSetup() public {
        // Expected board outcome:
        // 2:[0000|0110|0010|0000|0100] 1:[0001|0000|0010|0000|0100] 0:[0001|0000|0011|0000|0101]
        SlotParams memory params = SlotParams(3, 5, 6, 255, 255, 255, 95, 0, 5, 500, 1e18);
        uint256 layout = Board.generate(MAX_INT, params);

        // Check Row 0
        assertEq(Board.getFrom(layout, 0, 0, params.reels), 5);
        assertEq(Board.getFrom(layout, 0, 1, params.reels), 0);
        assertEq(Board.getFrom(layout, 0, 2, params.reels), 3);
        assertEq(Board.getFrom(layout, 0, 3, params.reels), 0);
        assertEq(Board.getFrom(layout, 0, 4, params.reels), 1);

        // Check Row 1
        assertEq(Board.getFrom(layout, 1, 0, params.reels), 4);
        assertEq(Board.getFrom(layout, 1, 1, params.reels), 0);
        assertEq(Board.getFrom(layout, 1, 2, params.reels), 2);
        assertEq(Board.getFrom(layout, 1, 3, params.reels), 0);
        assertEq(Board.getFrom(layout, 1, 4, params.reels), 1);

        // Check Row 2
        assertEq(Board.getFrom(layout, 2, 0, params.reels), 4);
        assertEq(Board.getFrom(layout, 2, 1, params.reels), 0);
        assertEq(Board.getFrom(layout, 2, 2, params.reels), 2);
        assertEq(Board.getFrom(layout, 2, 3, params.reels), 6);
        assertEq(Board.getFrom(layout, 2, 4, params.reels), 0);
    }

    function testGenerateInvalidSize() public {
        // Params with 13 columns (reels), 0 rows
        SlotParams memory params = SlotParams(0, 13, 6, 255, 255, 255, 95, 0, 5, 500, 1e18);
        vm.expectRevert("Invalid board size provided");
        uint256 layout = Board.generate(MAX_INT, params);
        assertEq(layout, 0);

        // Params with 13 columns, 5 rows (5 * 13 == 65)
        params.rows = 5;
        vm.expectRevert("Invalid board size provided");
        Board.generate(MAX_INT, params);
    
        // Params with 0 columns (reels), 5 rows
        params.reels = 0;
        vm.expectRevert("Invalid board size provided");
        Board.generate(MAX_INT, params);
    }

    function testGenerateMaxBoardSize() public {
        SlotParams memory params = SlotParams(8, 8, 15, 255, 255, 255, 95, 0, 5, 500, 1e18);
        Board.generate(MAX_INT, params);
    }

    function testGenerateInvalidSymbols() public {
        // Params with 16 symbols
        SlotParams memory params = SlotParams(3, 5, 16, 255, 255, 255, 95, 0, 5, 500, 1e18);
        vm.expectRevert("Invalid number of symbols provided");
        Board.generate(MAX_INT, params);

        // Params with 0 symbols (would cause the curve function to fail)
        params.symbols = 0;
        vm.expectRevert("Invalid number of symbols provided");
        Board.generate(MAX_INT, params);
    }

    function testGenerateInvalidPayoutConstant() public {
        SlotParams memory params = SlotParams(3, 5, 6, 255, 255, 255, 0, 0, 5, 500, 1e18);
        vm.expectRevert("Invalid payout constant provided");
        Board.generate(MAX_INT, params);
    }

    function testGenerateFuzz(uint256 entropy) public {
        Board.generate(
            MAX_INT,
            SlotParams(
                uint16(entropy % 8) + 1,    // columns
                uint16(entropy % 8) + 1,    // rows
                uint32(entropy % 15) + 1,   // symbolCount
                uint32(0),                  // wild
                uint32(0),                  // scatter
                uint32(0),                  // bonus
                uint32(entropy % 1000) + 1, // payoutConstant
                uint32(entropy % 100),      // payoutBottomLine
                uint16(0),                  // minBet
                uint16(0),                  // maxJackpot
                uint256(0)                  // creditSize
            )
        );
    }
}