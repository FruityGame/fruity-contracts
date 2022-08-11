// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/games/slots/MockSingleLineSlots.sol";

import { Board } from "src/libraries/Board.sol";

contract SlotsTest is Test {
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(255))));

    uint32 constant WILDCARD = 4;
    uint32 constant SCATTER = 5;

    MockSingleLineSlots slots;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        slots = new MockSingleLineSlots(
            SlotParams(3, 5, 6, WILDCARD, SCATTER, 255, 115, 20, 5, 500, 1e18),
            address(this)
        );
    }

    function testCheckWinline() public {
        //                                   4    3    2    1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0001|0000|0000|0000] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(4294967296);
        assertEq(symbol1, 0);
        assertEq(count1, 3);

        //                                   4    3    2    1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0000|0000|0001] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(1048576);
        assertEq(symbol2, 1);
        assertEq(count2, 1);

        //                                   4    3    2    1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0110|0110|0110|0110|0110] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol3, uint256 count3) = slots.checkWinlineExternal(439804231680);
        assertEq(symbol3, 6);
        assertEq(count3, 5);

        //                                   4    3    2    1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0110|0110|0110|0110] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol4, uint256 count4) = slots.checkWinlineExternal(27487371264);
        assertEq(symbol4, 6);
        assertEq(count4, 4);
    }

    function testCheckWinlineWithWildcard() public {
        //                                   4    3   2(W)  1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0100|0000|0000] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(1073741824);
        assertEq(symbol1, 0);
        assertEq(count1, 5);

        //                                   4    3   2(W)  1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0100|0110|0110] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(1180696576);
        assertEq(symbol2, 6);
        assertEq(count2, 3);

        //                                   4    3    2    1   0(W)
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0000|0110|0100] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol3, uint256 count3) = slots.checkWinlineExternal(104857600);
        assertEq(symbol3, 6);
        assertEq(count3, 2);

        //                                  4(W) 3(W) 2(W) 1(W) 0(W)
        // 2:[0000|0000|0000|0000|0000] 1:[0100|0100|0100|0100|0100] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol4, uint256 count4) = slots.checkWinlineExternal(293202821120);
        assertEq(symbol4, WILDCARD);
        assertEq(count4, 5);
    }

    function testCheckWinlineNoWildcard() public {
        // Configure slots to have no wildcard set (set wildcard to 255)
        MockSingleLineSlots slotsNoWildcard = new MockSingleLineSlots(
            SlotParams(3, 5, 6, 255, SCATTER, 255, 115, 20, 5, 500, 1e18),
            address(this)
        );

        // Test with 'wildcard' in middle
        //                                   4    3   2(W)  1    0
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0100|0000|0000] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol1, uint256 count1) = slotsNoWildcard.checkWinlineExternal(1073741824);
        assertEq(symbol1, 0);
        assertEq(count1, 2);

        // Test with 'wildcard' start
        //                                   4    3    2    1   0(W)
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0000|0110|0100] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol2, uint256 count2) = slotsNoWildcard.checkWinlineExternal(104857600);
        assertEq(symbol2, 4);
        assertEq(count2, 1);
    }

    function testCheckWinlineWithScatterStart() public {
        //                                   4    3    2    1   0(S)
        // 2:[0000|0000|0000|0000|0000] 1:[0101|0101|0101|0101|0101] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(366503526400);
        assertEq(symbol1, 0);
        assertEq(count1, 0);

        //                                   4    3    2    1   0(S)
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0000|0000|0101] 0:[0000|0000|0000|0000|0000]
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(5242880);
        assertEq(symbol2, 0);
        assertEq(count2, 0);
    }

    function testPlaceBetFuzz(uint256 entropy) public {
        uint256 credits = (entropy % 5) + 1;
        uint256 betId = slots.placeBet(credits);
        slots.fulfillRandomnessExternal(betId, WINNING_ENTROPY);

        assertEq(slots.balance(), credits * 1e18);
        assertEq(slots.jackpotWad(), credits * 1e16);
    }

    function testPlaceBetTooManyCredits() public {
        SlotParams memory params = slots.getParams();

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSlots.BetTooLarge.selector,
                params.maxBetCredits + 1, params.maxBetCredits
            )
        );
        slots.placeBet(params.maxBetCredits + 1);

        // Ensure no bet has been consumed
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetNoCredits() public {        
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSlots.BetTooSmall.selector,
                0, 1
            )
        );
        slots.placeBet(0);

        // Ensure no bet has been consumed
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testCancelBetFuzz(uint256 entropy) public {
        uint256 credits = (entropy % 5) + 1;
        uint256 betId = slots.placeBet(credits);

        assertEq(slots.balance(), credits * 1e18);
        assertEq(slots.jackpotWad(), 0);

        slots.cancelBet(betId);
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }
}