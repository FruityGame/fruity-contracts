// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/slots/MockMuliLineSlots.sol";
import "test/mocks/MockChainlinkVRF.sol";

import "src/libraries/Board.sol";
import "src/payment/PaymentProcessor.sol";

contract SlotsTest is Test {
    // 01|01|01|01|01
    uint256 constant WINLINE = 341;
    // 01|10|11|10|01
    uint256 constant WINLINE_WINNER = 441;
    // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
    uint256 constant BOARD = 281479288520705;
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(255))));
    // Full set of 5x5 winlines, representitive of the lines in mockWinlines()
    uint256 constant WINLINES_FULL = 536169616821538800036600934927570202961204380927034107000682;

    uint32 constant WILDCARD = 4;
    uint32 constant SCATTER = 5;

    MockMuliLineSlots slots;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        slots = new MockMuliLineSlots(
            SlotParams(3, 5, 6, WILDCARD, SCATTER, 255, 115, 20, 5, 1e18),
            mockWinlines()
        );
    }

    function testCheckWinline() public {
        //                                                                4    3    2    1    0
        // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(BOARD, WINLINE);
        assertEq(symbol1, 1);
        assertEq(count1, 1);

        //                2                       3         1             4                   0
        // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(BOARD, WINLINE_WINNER);
        assertEq(symbol2, 1);
        assertEq(count2, 5);
    }

    function testCheckWinlineWithWildcard() public {
        //                                                                4    3    2    1    0
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        uint256 boardWithWildcard = 1125917103554561;
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(boardWithWildcard, WINLINE);
        assertEq(symbol1, 1);
        assertEq(count1, 1);

        //               2 (wildcard)             3         1             4                   0
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(boardWithWildcard, WINLINE_WINNER);
        assertEq(symbol2, 1);
        assertEq(count2, 5);

        //                                                                4    3    2   1(W)  0
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0100|0001]
        uint256 boardWithWildcardSplit = 1125899923685441;
        (uint256 symbol3, uint256 count3) = slots.checkWinlineExternal(boardWithWildcardSplit, WINLINE);
        assertEq(symbol3, 1);
        assertEq(count3, 2);

        //               2 (wildcard)             3         1             4                   0
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0100|0001]
        (uint256 symbol4, uint256 count4) = slots.checkWinlineExternal(boardWithWildcardSplit, WINLINE_WINNER);
        assertEq(symbol4, 1);
        assertEq(count4, 3);
    }

    function testCheckWinlineNoWildcard() public {
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
    }

    function mockWinlines() private pure returns (uint256[] memory out) {
        out = new uint256[](20);
        out[0] = 341; out[1] = 682; out[2] = 1023; out[3] = 630; out[4] = 871;
        out[5] = 986; out[6] = 671; out[7] = 473; out[8] = 413; out[9] = 854;
        out[10] = 599; out[11] = 873; out[12] = 637; out[13] = 869; out[14] = 629;
        out[15] = 474; out[16] = 415; out[17] = 985; out[18] = 669; out[19] = 874;
    }
}