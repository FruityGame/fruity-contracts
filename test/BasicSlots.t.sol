// SPDX-License-Identifier: MIT
/*pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Board.sol";
import "src/Slots.sol";
import "test/harnesses/SlotsTestHarness.sol";
import "test/mocks/MockChainlinkVRF.sol";
import "test/mocks/MockSlotsReentrancy.sol";

contract SlotsTest is Test {
    // 01|01|10|10|01
    uint256 constant WINLINE_STUB = 361;
    uint256 constant WINLINE_WINNER_STUB = 890;
    uint256 constant internal WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(255))));
    uint256 constant SLOTS_FUNDS = 100 * 1e18;
    // Full set of Fruity 5x5 winlines
    uint256 constant WINLINES_FULL = 536169616821538800036600934927570202961204380927034107000682;
    MockChainlinkVRF vrf;
    SlotsTestHarness slots;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        vrf = new MockChainlinkVRF();
        slots = new SlotsTestHarness(
            VRFParams(address(vrf), address(0), bytes32(0), 0),
            SlotParams(15, 5, 6, 115, 20, 1e15),
            new uint8[](0)
        );

        deal(address(slots), SLOTS_FUNDS);
        deal(address(this), SLOTS_FUNDS);
    }

    // Ensure our winline function is parsing symbols as expected
    function testCheckWinline() public {
        // 2: [0100|0001|0100|0000|0011] 1: [0001|0000|0010|0100|0011] 0: [0001|0100|0010|0110|0011]
        uint256 board = Board.generate(WINNING_ENTROPY, 15, 6, 115, 20);
        // 01|01|10|10|01
        // [row 0, index 4], [row 0, index 3], [row 1, index 2] [row 1, index 1] [row 0, index 0]
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(board, WINLINE_STUB);
        assertEq(symbol1, 0);
        assertEq(count1, 0);

        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(board, WINLINE_WINNER_STUB);
        assertEq(symbol2, 4);
        assertEq(count2, 4);
    }

    function testCheckWinlineInvalidBoard() public {
        vm.expectRevert("Invalid symbol parsed from board for this contract");
        slots.checkWinlineExternal(256**2 - 1, WINLINE_STUB);
    }

    function testCountWinlines() public {
        // Count all 20 unique winlines for 5x5 slots
        assertEq(slots.countWinlinesExternal(WINLINES_FULL), 20);
    }

    function testCountWinlinesDuplicate() public {
        uint256 duplicateWinline = (WINLINE_STUB << 10) | WINLINE_STUB;

        vm.expectRevert("Duplicate item detected");
        slots.countWinlinesExternal(duplicateWinline);
    }

    function testPlaceBet() public {
        uint256 bet = 1e18;
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(WINNING_ENTROPY, vrf.requestId());

        // Ensure our bet has been taken and the jackpot incremented
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        // In WEI, should equal 0.333333333333333333 Ether
        assertEq(slots.jackpotWad(), 1e16);
    }

    function testPlaceBetPayoutInsufficientFunds() public {
        // Place our bet with a winning winline (to trigger payout)
        uint256 betId = slots.placeBet{value: 1e18}(1e18, WINLINE_WINNER_STUB);
        uint256 expectedPayout = 1e18 * 20;
        deal(address(slots), expectedPayout + 1e6);

        // Fulfill the bet
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure we've been paid out what was remaining in the slots, minus the jackpot and our original bet
        assertEq(address(this).balance, SLOTS_FUNDS + 1e6 + (expectedPayout - slots.jackpotWad() - 1e18));
        // Ensure the slots still contains enough of a balance to payout the jackpot
        assertEq(address(slots).balance, slots.jackpotWad());
    }

    function testInsufficientJackpotInvariant() public {
        // Place our bet with a winning winline (to trigger payout)
        uint256 betId = slots.placeBet{value: 1e18}(1e18, WINLINE_WINNER_STUB);
        // Set our balance to be below the jackpot threshold
        deal(address(slots), 1e6);

        // Fulfill the bet
        vm.expectRevert("Invariant in jackpot balance detected");
        slots.fulfillRandomnessExternal(WINNING_ENTROPY, betId);

        // Ensure the slots still contains the balance we set
        assertEq(address(slots).balance, 1e6);
    }

    function testPlaceBetInvalidAmountForWinlines() public {
        uint256 bet = 1e18;
        // Pass in two winlines
        vm.expectRevert("Amount provided not enough to cover bet");
        slots.placeBet{value: bet}(bet, 349801);
        vrf.fulfill(WINNING_ENTROPY, vrf.requestId());

        // Ensure parity of balances
        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, SLOTS_FUNDS);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetTooSmall() public {
        uint256 bet = 1e6;
        vm.expectRevert(
            abi.encodeWithSelector(Slots.BetTooSmall.selector, 1e6, 1e15)
        );
        slots.placeBet{value: bet}(bet, WINLINE_STUB);

        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, SLOTS_FUNDS);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetTooLarge() public {
        // Attempt to place a bet larger than the balance of the contract
        vm.expectRevert("Bet too large for contract payout");
        slots.placeBet{value: (SLOTS_FUNDS / 2) + 1}((SLOTS_FUNDS / 2) + 1, WINLINE_STUB);

        // Ensure balaces are correct
        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, SLOTS_FUNDS);
        assertEq(slots.jackpotWad(), 0);

        // Set the balance of the contract to zero
        deal(address(slots), 0);

        // Attempt to place a bet of size 1
        vm.expectRevert("Bet too large for contract payout");
        slots.placeBet{value: 1e18}(1e18, WINLINE_STUB);

        // Ensure balaces are correct
        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetInvalidIntoValid() public {
        uint256 bet = 1e18;
        // Pass in two winlines, invalid value to cover the cost
        vm.expectRevert("Amount provided not enough to cover bet");
        slots.placeBet{value: bet}(bet, 349801);

        // Ensure our balance remains the same
        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, SLOTS_FUNDS);
        assertEq(slots.jackpotWad(), 0);

        // Place a new bet after the failure
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure parity of balances
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 1e16);
    }

    function testCancelBet() public {
        uint256 bet = 1e18;

        // Place our bet
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);

        // Ensure our bet has been added to the slots correctly
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);

        // Cancel our bet
        slots.cancelBet(betId);

        // In a real world scenario, the chainlink VRF callback would fail to resolve,
        // as we no longer have an active sessionId to resolve
        vm.expectRevert("User Session has already been resolved");
        slots.fulfillRandomnessExternal(WINNING_ENTROPY, betId);
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure we've not been charged for the VRF Fulfillment and have
        // successfully been reimbursed
        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, SLOTS_FUNDS);
        assertEq(slots.jackpotWad(), 0);
    }

    function testCancelBetInsufficientFunds() public {
        // Place our bet
        uint256 betId = slots.placeBet{value: 1e18}(1e18, WINLINE_STUB);

        // Set the slots balance to 0
        deal(address(slots), 0);

        // Attempt to cancel our bet
        vm.expectRevert("Insufficient funds in contract to process refund");
        slots.cancelBet(betId);
    }

    function testCancelBetInsufficientFundsJackpot() public {
        // Place our bet
        uint256 betId = slots.placeBet{value: 1e18}(1e18, WINLINE_STUB);

        // Set the slots balance to the jackpot value
        deal(address(slots), slots.jackpotWad());

        // Ensure the cancelBet logic takes into account maintaining a balance sufficient enough to payout a jackpot
        vm.expectRevert("Insufficient funds in contract to process refund");
        slots.cancelBet(betId);

        // Ensure the slots balance is still enough to payout the jackpot
        assertEq(address(slots).balance, slots.jackpotWad());
    }

    function testCancelBetAlreadyFulfilledBet() public {
        uint256 bet = 1e18;
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Attempt to cancel with no active bet
        vm.expectRevert("Cannot cancel already fulfilled bet");
        slots.cancelBet(betId);

        // Ensure we've not been credited a balance by some invariant
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 1e16);
    }

    function testCancelBetInvalidUser() public {
        uint256 bet = 1e18;

        // Place a bet
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);

        // Attempt to cancel our bet with a different address
        vm.expectRevert("Invalid session requested for user");
        vm.prank(address(0));
        slots.cancelBet(betId);

        // Ensure balances are unchanged after failed cancel
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 0);

        // Fulfill the bet
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure parity of balances
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 1e16);
    }

    function testCancelBetInvalidSessionId() public {
        uint256 bet = 1e18;

        // Place a bet
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);

        // Attempt to cancel a complete or uninitialized bet
        vm.expectRevert("Cannot cancel already fulfilled bet");
        slots.cancelBet(123);

        // Ensure parity of balances
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 0);

        // Fulfill the bet
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure parity of balances
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 1e16);
    }

    // Simulate a situation in which the VRF returns an old session ID for a user
    function testFulfillInvalidSessionId() public {
        uint256 bet = 1e18;

        // Immediately place and cancel our bet
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);
        slots.cancelBet(betId);

        // Place another bet, simulate a theoretical scenario in which the VRF
        // returns for a previous session
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(WINNING_ENTROPY, betId);

        // We still have an active bet, so verify that our deposit is still there
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 0);

        // Valid VRF fulfillment for the current user's bet:requestId
        vrf.fulfill(WINNING_ENTROPY, vrf.requestId());

        // Jackpot has now been taken, successful
        assertEq(address(this).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 1e16);
    }

    // This test tests for reentrancy from fulfillRandomness into cancelBet
    // a scenario in which a user could attempt to cancel their bet during the payout
    // to receive both the payout and their bet back
    function testFulfillCancelReentrancy() public {
        uint256 bet = 1e18;
        // Setup our reentrancy contract. The contract attempts to call
        // cancelBet on the contract during the bet payout stage
        MockSlotsCancelReentrancy maliciousContract = new MockSlotsCancelReentrancy();
        deal(address(maliciousContract), SLOTS_FUNDS);

        // Set the caller address for this function invocation to be the
        // malicious contracts, as if the contract were calling to place a bet
        vm.prank(address(maliciousContract));
        // Place a bet with a winning winline (will call payout)
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_WINNER_STUB);
        // Setup the malicious contract to attempt to cancel our betId with reentrancy
        maliciousContract.setBetId(betId);

        // Ensure that the VRF Callback fails, due to reentrancy
        vm.expectRevert("Failed to payout win");
        slots.fulfillRandomnessExternal(WINNING_ENTROPY, betId);
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure the user, even though they're malicious, still have their bet active,
        // so it can still be withdrawn at a later date if need be. Ensure jackpot has not
        // been incremented
        assertEq(address(maliciousContract).balance, SLOTS_FUNDS - bet);
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        assertEq(slots.jackpotWad(), 0);
    }

    // This test tests for a reentrancy scenario in which a user could attempt to cancel their
    // bet multiple times in succession with reentrancy, which would allow them to drain the contract
    function testCancelSameBetReentrancy() public {
        uint256 bet = 1e18;
        // Setup our reentrancy contract. The contract calls
        // cancelBet upon receiving funds
        MockSlotsCancelReentrancy maliciousContract = new MockSlotsCancelReentrancy();
        deal(address(maliciousContract), SLOTS_FUNDS);

        // Set the caller address for this function invocation to be the
        // malicious contracts, as if the contract were calling to place a bet
        vm.prank(address(maliciousContract));
        // Place a bet with a winning winline (will call payout)
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_WINNER_STUB);
        // Setup the malicious contract to attempt to cancel our second betID
        maliciousContract.setBetId(betId);

        // Cancel our bet, the contract will attempt to cancel the same bet when it receives() funds
        vm.expectRevert("Failed to cancel bet");
        vm.prank(address(maliciousContract));
        slots.cancelBet(betId);

        vm.expectRevert("Failed to payout win");
        slots.fulfillRandomnessExternal(WINNING_ENTROPY, betId);
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(WINNING_ENTROPY, betId);

        // Ensure the user, even though they're malicious, still have their bet active,
        // so it can still be withdrawn at a later date if need be. Ensure jackpot has not
        // been incremented
        assertEq(address(maliciousContract).balance, SLOTS_FUNDS - bet);
        // Ensure our bet has not been withdrawn maliciously
        assertEq(address(slots).balance, SLOTS_FUNDS + bet);
        // Ensure jackpot has not been incremented
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetDefaultWinlineFuzz(bytes32 entropy) public {
        uint256 randomness = uint256(keccak256(abi.encodePacked(entropy)));
        // 682 is 1010101010, Aka Only Row 1 / Middle Row
        slots.fulfillRandomnessExternal(
            randomness,
            slots.placeBet{value: 1e18}(1e18, 682)
        );
    }

    function testPlaceBetRandomWinlineFuzz(bytes32 entropy) public {
        uint256 randomness = uint256(keccak256(abi.encodePacked(entropy)));

        // Generate a random selection of winlines from the above entropy
        uint256 winlines = WINLINES_FULL & 1023;
        uint256 count = (randomness % 10) + 1;
        for (uint256 j = 0; j < count; j++) {
            winlines = (winlines << 10) | ((WINLINES_FULL >> 10 * (count - j)) & 1023);
        }

        slots.fulfillRandomnessExternal(
            randomness,
            slots.placeBet{value: 1e16 * (count + 1)}(1e16, winlines)
        );
    }

    /*function testWinRateNormalWinline() public {
        // 1 Ether
        uint256 bet = 1e18 * 10;

        //deal(address(slots), 1000 * 1e18);
        //deal(address(this), 1000 * 1e18);

        for (uint256 i = 0; i < 500; i++) {
            uint256 randomness = uint256(keccak256(abi.encodePacked(uint256(3452123223234511), i)));
            slots.fulfillRandomnessExternal(randomness, slots.placeBet{value: bet}(bet, 682));
        }

        emit log_uint(slots.jackpotWad() / 1e18);
        emit log_uint(address(slots).balance / 1e18);
        emit log_uint(address(this).balance / 1e18);
    }*/

    /*function testWinRateRandomWinlines() public {
        uint256 bet = 1e18 * 5;

        deal(address(this), 1000 * 1e18);
        deal(address(slots), 1000 * 1e18);

        for (uint256 i = 0; i < 100; i++) {
            uint256 randomness = uint256(keccak256(abi.encodePacked(uint256(0xfc78e2ba), i)));
            uint256 winlines = WINLINES_FULL & 1023;
            uint256 count = (randomness % 10) + 1;
            for (uint256 j = 0; j < count; j++) {
                winlines = (winlines << 10) | ((WINLINES_FULL >> 10 * (count - j)) & 1023);
            }
            slots.fulfillRandomnessExternal(randomness, slots.placeBet{value: bet * (count + 1)}(bet, winlines));
        }

        emit log_uint(slots.jackpotWad() / 1e18);
        emit log_uint(address(slots).balance / 1e18);
        emit log_uint(address(this).balance / 1e18);
    }*/
//}