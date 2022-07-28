// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Board.sol";

contract BoardTest is Test {
    uint256 constant internal MAX_INT = 2**256 - 1;

    function setUp() public virtual {}

    function testSetup() public {
        // Expected board outcome:
        // 2:[0000|0110|0010|0000|0100] 1:[0001|0000|0010|0000|0100] 0:[0001|0000|0011|0000|0101]
        uint256 layout = Board.generate(MAX_INT, 15, 6, 95, 0);

        // Check Row 0
        assertEq(Board.getWithRow(layout, 0, 0, 5), 5);
        assertEq(Board.getWithRow(layout, 0, 1, 5), 0);
        assertEq(Board.getWithRow(layout, 0, 2, 5), 3);
        assertEq(Board.getWithRow(layout, 0, 3, 5), 0);
        assertEq(Board.getWithRow(layout, 0, 4, 5), 1);

        // Check Row 1
        assertEq(Board.getWithRow(layout, 1, 0, 5), 4);
        assertEq(Board.getWithRow(layout, 1, 1, 5), 0);
        assertEq(Board.getWithRow(layout, 1, 2, 5), 2);
        assertEq(Board.getWithRow(layout, 1, 3, 5), 0);
        assertEq(Board.getWithRow(layout, 1, 4, 5), 1);

        // Check Row 2
        assertEq(Board.getWithRow(layout, 2, 0, 5), 4);
        assertEq(Board.getWithRow(layout, 2, 1, 5), 0);
        assertEq(Board.getWithRow(layout, 2, 2, 5), 2);
        assertEq(Board.getWithRow(layout, 2, 3, 5), 6);
        assertEq(Board.getWithRow(layout, 2, 4, 5), 0);
    }

    function testGenerateInvalidSize() public {
        // Test 0 size
        vm.expectRevert("Invalid board size provided");
        uint256 layout = Board.generate(MAX_INT, 0, 2, 114, 20);
        assertEq(layout, 0);
        // Test > 64 size
        vm.expectRevert("Invalid board size provided");
        Board.generate(MAX_INT, 65, 6, 115, 20);
    }

    function testGenerateMax() public {
        Board.generate(MAX_INT, 64, 15, 115, 20);
    }

    function testGenerateInvalidSymbols() public {
        // Test 16 symbols
        vm.expectRevert("Invalid number of symbols provided");
        Board.generate(MAX_INT, 15, 16, 115, 20);
        // Test 0 symbols (would cause the curve function to fail)
        vm.expectRevert("Invalid number of symbols provided");
        Board.generate(MAX_INT, 15, 0, 115, 20);
    }

    function testGenerateInvalidPayoutConstant() public {
        vm.expectRevert("Invalid payout constant provided");
        Board.generate(MAX_INT, 15, 7, 0, 20);
    }

    function testGenerateFuzz(uint256 entropy) public {
        Board.generate(MAX_INT, (entropy % 25) + 1, (entropy % 15) + 1, (entropy % 1000) + 1, entropy % 100);
    }

    /*function testSymbolRate() public {
        uint256[7] memory symbolCount = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
        for (uint256 i = 0; i < 1000; i++) {
            uint256 randomness = uint256(keccak256(abi.encodePacked(i)));
            uint256 layout = Board.generate(randomness, 15, 6, 115, 20);

            for (uint256 j = 0; j < 3; j++) {
                symbolCount[Board.getWithRow(layout, j, 0, 5)] += 1;
                symbolCount[Board.getWithRow(layout, j, 1, 5)] += 1;
                symbolCount[Board.getWithRow(layout, j, 2, 5)] += 1;
                symbolCount[Board.getWithRow(layout, j, 3, 5)] += 1;
                symbolCount[Board.getWithRow(layout, j, 4, 5)] += 1;
            }
        }

        for (uint256 j = 0; j < 7; j++) {
            emit log_uint(j);
            emit log_uint(symbolCount[j]);
        }
    }*/
}
