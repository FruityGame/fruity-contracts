// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/slots/MockMuliLineSlots.sol";

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
            SlotParams(3, 5, 6, WILDCARD, SCATTER, 255, 115, 20, 5, 500, 1e18),
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

        //                                                                4    3    2   1(W) 0(W)
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0000|0000|0000] 0:[0000|0000|0000|0100|0100]
        (uint256 symbol5, uint256 count5) = slots.checkWinlineExternal(68, WINLINE);
        assertEq(symbol5, 0);
        assertEq(count5, 5);

        //                                                                4    3    2   1(W) 0(W)
        // 2:[0000|0000|0000|0000|0000] 1:[0000|0000|0000|0000|0000] 0:[0100|0100|0100|0100|0100]
        (uint256 symbol6, uint256 count6) = slots.checkWinlineExternal(279620, WINLINE);
        assertEq(symbol6, WILDCARD);
        assertEq(count6, 5);
    }

    function testCheckWinlineNoWildcard() public {
        // Configure slots to have no wildcard set (set wildcard to 255)
        MockMuliLineSlots slotsNoWildcard = new MockMuliLineSlots(
            SlotParams(3, 5, 6, 255, SCATTER, 255, 115, 20, 5, 500, 1e18),
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

    function testCountWinlinesFuzz(uint256 entropy) public {
        // Generate a random selection of winlines from the above entropy
        // ( yes its bad I know, no I'm not sorry (<: )
        bool[] memory lines = new bool[](20);
        uint256 winlines = WINLINES_FULL & 1023;
        uint256 winlineCount = 1;
        lines[0] = true;
        // Pick a random number of winlines between 1-20
        for (uint256 j = (entropy % 19) + 1; j < 20; j++) {
            // Generate a pseudorandom index
            uint256 index = (2**j) % (20 - j);

            // If we've not already chosen this winline, add it to the lines and increment
            // the expected count
            if (!lines[index]) {
                winlines = (winlines << 10) | ((WINLINES_FULL >> 10 * index) & 1023);
                lines[index] = true;
                winlineCount++;
            }
        }

        assertEq(slots.countWinlinesExternal(winlines), winlineCount);
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

    function testCancelBetSingleWinline() public {
        uint256 betId = slots.placeBet(1, WINLINE);

        // Ensure 20 * (credit) has been added to the balance
        assertEq(slots.balance(), 1e18);
        assertEq(slots.jackpotWad(), 0);

        // Ensure cancel bet factors in the number of winlines in our bet
        slots.cancelBet(betId);
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

    function testCancelBetMaxValue() public {
        uint256 betId = slots.placeBet(5, WINLINES_FULL);

        // Ensure 20 * 5 * (credit) has been added to the balance
        assertEq(slots.balance(), 5 * 20e18);
        assertEq(slots.jackpotWad(), 0);

        // Ensure cancel bet factors in the number of winlines in our bet
        slots.cancelBet(betId);
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);
    }

    // TODO: Mock resolveSymbol with MockMultiLineSlots to enable this test
    /*function testPlaceCancelFulfillBetRandomWinlineFuzz(bytes32 entropy) public {
        uint256 randomness = uint256(keccak256(abi.encodePacked(entropy)));
        uint256 credits = (randomness % 5) + 1;

        // Generate a random selection of winlines from the above entropy
        // ( yes its bad I know, no I'm not sorry (<: )
        bool[] memory lines = new bool[](20);
        uint256 winlines = WINLINES_FULL & 1023;
        uint256 winlineCount = 1;
        lines[0] = true;
        // Pick a random number of winlines between 1-20
        for (uint256 j = (randomness % 19) + 1; j < 20; j++) {
            // Generate a pseudorandom index
            uint256 index = (2**j) % (20 - j);

            // If we've not already chosen this winline, add it to the lines and increment
            // the expected count
            if (!lines[index]) {
                winlines = (winlines << 10) | ((WINLINES_FULL >> 10 * index) & 1023);
                lines[index] = true;
                winlineCount++;
            }
        }

        // Ensure we don't payout so we don't skew the asserts below
        vm.mockCall(
            address(slots),
            abi.encodeWithSelector(BaseSlots.resolveSymbol.selector),
            abi.encode(0)
        );

        // Place our bet
        uint256 betId = slots.placeBet(credits, winlines);
        assertEq(slots.balance(), credits * 1e18 * winlineCount);
        assertEq(slots.jackpotWad(), 0);

        // Cancel our bet
        slots.cancelBet(betId);
        assertEq(slots.balance(), 0);
        assertEq(slots.jackpotWad(), 0);

        // Place our bet and fulfill it
        slots.fulfillRandomnessExternal(
            slots.placeBet(credits, winlines),
            0
        );

        emit log_uint(winlines);
        emit log_uint(slots.countWinlinesExternal(winlines));
        assertEq(slots.balance(), credits * 1e18 * winlineCount);
        assertEq(slots.jackpotWad(), credits * 1e16 * (winlineCount + 1));
    }*/

    function testMaxedJackpot() public {
        SlotParams memory params = slots.getParams();
        uint256 maxJackpot = params.maxJackpotCredits * params.creditSizeWad;

        // Set to max jackpot
        slots.setJackpot(maxJackpot);
        assertEq(slots.jackpotWad(), maxJackpot);

        // Resolve a bet
        uint256 betId = slots.placeBet(1, WINLINES_FULL);
        slots.fulfillRandomnessExternal(betId, WINNING_ENTROPY);

        // Ensure jackpot has not incremented beyond the max
        assertEq(slots.jackpotWad(), maxJackpot);
    }

    function mockWinlines() private pure returns (uint256[] memory out) {
        out = new uint256[](20);
        out[0] = 341; out[1] = 682; out[2] = 1023; out[3] = 630; out[4] = 871;
        out[5] = 986; out[6] = 671; out[7] = 473; out[8] = 413; out[9] = 854;
        out[10] = 599; out[11] = 873; out[12] = 637; out[13] = 869; out[14] = 629;
        out[15] = 474; out[16] = 415; out[17] = 985; out[18] = 669; out[19] = 874;
    }
}