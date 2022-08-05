// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/slots/MockSingleLineSlots.sol";
import "test/mocks/MockChainlinkVRF.sol";

import "src/libraries/Board.sol";
//import "src/payment/PaymentProcessor.sol";

contract SlotsTest is Test {
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(255))));

    uint32 constant WILDCARD = 4;
    uint32 constant SCATTER = 5;

    MockSingleLineSlots slots;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        slots = new MockSingleLineSlots(
            SlotParams(3, 5, 6, WILDCARD, SCATTER, 255, 115, 20, 5, 500, 1e18)
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

    /*function testCheckWinlineNoWildcard() public {
        // Configure slots to have no wildcard set (set wildcard to 255)
        MockMuliLineSlots slotsNoWildcard = new MockMuliLineSlots(
            SlotParams(3, 5, 6, 255, SCATTER, 255, 115, 20, 5, 1e18),
            mockWinlines()
        );

        //                                                                4    3    2    1    0
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        uint256 boardWithWildcard = 1125917103554561;
        (uint256 symbol1, uint256 count1) = slotsNoWildcard.checkWinlineExternal(boardWithWildcard, WINLINE);
        assertEq(symbol1, 1);
        assertEq(count1, 1);

        //               2 (wildcard)             3         1             4                   0
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        (uint256 symbol2, uint256 count2) = slotsNoWildcard.checkWinlineExternal(boardWithWildcard, WINLINE_WINNER);
        assertEq(symbol2, 1);
        assertEq(count2, 2);
    }

    function testCheckWinlineWithScatterStart() public {
        //                                                                4    3    2    1   0(S)
        // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0000|0101]
        uint256 boardWithScatterStart = 281479288520709;
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(boardWithScatterStart, WINLINE);
        assertEq(symbol1, 0);
        assertEq(count1, 0);

        //                2                       3(S)      1             4                   0
        // 2:[0000|0000|0001|0000|0000] 1:[0000|0101|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        uint256 boardWithScatterMiddle = 281496468389889;
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(boardWithScatterMiddle, WINLINE_WINNER);
        assertEq(symbol2, 1);
        assertEq(count2, 3);
    }

    function testCountWinlines() public {
        assertEq(slots.countWinlinesExternal(WINLINE), 1);
        // Count 20 unique winlines for 5x5 slots
        assertEq(slots.countWinlinesExternal(WINLINES_FULL), 20);
    }

    function testCountWinlinesZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiLineSlots.InvalidWinlineCount.selector,
                0
            )
        );
        slots.countWinlinesExternal(0);
    }

    function testCountWinlinesDuplicate() public {
        uint256 duplicateWinline = (WINLINE << 10) | WINLINE;

        vm.expectRevert("Duplicate item detected");
        slots.countWinlinesExternal(duplicateWinline);
    }

    function testCountWinlinesInvalidWinline() public {
        vm.expectRevert("Invalid winline parsed for contract");
        slots.countWinlinesExternal(614);
    }

    function testPlaceBetSingleWinline() public {
        uint256 betId = slots.placeBet(1, WINLINE);
        slots.fulfillRandomnessExternal(betId, WINNING_ENTROPY);

        // Ensure our bet has been taken and we've been
        // charged 1 (winline count) * 1e18 (credit)
        assertEq(slots.balance(), 1e18);
        // In WEI, should equal 0.333333333333333333 Token
        assertEq(slots.jackpotWad(), 1e16);
    }

    function testPlaceBetNoWinlines() public {        
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiLineSlots.InvalidWinlineCount.selector,
                0
            )
        );
        slots.placeBet(1, 0);

        // Ensure no bet has been consumed
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetMultipleWinlines() public {
        uint256 betId = slots.placeBet(1, WINLINES_FULL);
        // Ensure 20 * (credit) has been added to the balance
        assertEq(slots.balance(), 20e18);

        slots.fulfillRandomnessExternal(betId, WINNING_ENTROPY);
        // Ensure 1/100th of the bet (default jackpot configuration)
        // has been added to jackpot
        assertEq(slots.jackpotWad(), 20e18 / 100);
    }

    function testPlaceBetTooManyCredits() public {
        SlotParams memory params = slots.getParams();
        
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSlots.BetTooLarge.selector,
                params.maxBetCredits + 1, params.maxBetCredits
            )
        );
        slots.placeBet(params.maxBetCredits + 1, WINLINE);

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
        slots.placeBet(0, WINLINE);

        // Ensure no bet has been consumed
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testCancelBetMultipleWinlines() public {
        uint256 betId = slots.placeBet(1, WINLINES_FULL);

        // Ensure 20 * (credit) has been added to the balance
        assertEq(slots.balance(), 20e18);
        assertEq(slots.jackpotWad(), 0);

        // Ensure cancel bet factors in the number of winlines in our bet
        slots.cancelBet(betId);
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }*/
}