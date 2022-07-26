// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Board.sol";
import "test/harnesses/SlotsTestHarness.sol";
import "test/mocks/MockChainlinkVRF.sol";
import "test/mocks/MockSlotsReentrancy.sol";

contract SlotsTest is Test {
    // 01|01|10|10|01
    uint256 constant WINLINE_STUB = 361;
    uint256 constant internal MAX_INT = 2**256 - 1;
    MockChainlinkVRF vrf;
    SlotsTestHarness slots;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        vrf = new MockChainlinkVRF();
        slots = new SlotsTestHarness(
            address(vrf),
            address(0),
            bytes32(0),
            0
        );

        deal(address(this), 100 * (10 ** 18));
    }

    function testCheckWinline() public {
        // 2:[0001|0001|0001|0000|0001] 1:[0010|0011|0100|0011|0011] 0:[0001|0000|0100|0011|0000]
        uint256 board = Board.generate(MAX_INT);
        // 01|01|10|10|01
        // [row 0, index 4], [row 0, index 3], [row 1, index 2] [row 1, index 1] [row 0, index 0]
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(board, WINLINE_STUB);
        assertEq(symbol1, 0);
        assertEq(count1, 2);

        // 1023 = 11|11|11|11|11
        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(board, 1023);
        assertEq(symbol2, 1);
        assertEq(count2, 4);
    }

    function testCheckWinlineInvalidBoard() public {
        vm.expectRevert("Invalid symbol parsed from board for this contract");
        slots.checkWinlineExternal(MAX_INT, WINLINE_STUB);
    }

    function testPlaceBet() public {
        uint256 bet = 1 * (10 ** 18);
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(MAX_INT, vrf.requestId());

        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        // In WEI, should equal 0.333333333333333333 Ether
        assertEq(slots.jackpotWad(), 333333333333333333);
    }

    function testPlaceBetInvalidAmountForWinlines() public {
        uint256 bet = 1 * (10 ** 18);
        // Pass in two winlines
        vm.expectRevert("Amount provided not enough to cover bet");
        slots.placeBet{value: bet}(bet, 349801);
        vrf.fulfill(MAX_INT, vrf.requestId());

        assertEq(address(this).balance, 100 * (10 ** 18));
        assertEq(address(slots).balance, 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetTooSmall() public {
        uint256 bet = 1 * (10 ** 6);
        vm.expectRevert("Bet must be at least 1000000 Gwei");
        slots.placeBet{value: bet}(bet, WINLINE_STUB);

        assertEq(address(this).balance, 100 * (10 ** 18));
        assertEq(address(slots).balance, 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testPlaceBetInvalidIntoValid() public {
        uint256 bet = 1 * (10 ** 18);
        // Pass in two winlines, invalid value to cover
        vm.expectRevert("Amount provided not enough to cover bet");
        slots.placeBet{value: bet}(bet, 349801);
        vrf.fulfill(MAX_INT, vrf.requestId());

        // Place a new bet after the failure
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(MAX_INT, vrf.requestId());

        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpotWad(), 333333333333333333);
    }

    function testCancelBet() public {
        uint256 bet = 1 * (10 ** 18);
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);

        // Ensure our bet has been added to the slots correctly
        assertEq(address(slots).balance, bet);

        // Cancel our bet
        slots.cancelBet(betId);

        // In a real world scenario, the chainlink VRF callback would fail to resolve,
        // as we no longer have an active sessionId to resolve
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(MAX_INT, betId);

        // Ensure we've not been charged for the VRF Fulfillment and have
        // successfully been reimbursed
        assertEq(address(this).balance, 100 * (10 ** 18));
        assertEq(address(slots).balance, 0);
        assertEq(slots.jackpotWad(), 0);
    }

    function testCancelBetAlreadyFulfilledBet() public {
        uint256 bet = 1 * (10 ** 18);
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(MAX_INT, betId);

        // Attempt to cancel with no active bet
        vm.expectRevert("Cannot cancel already fulfilled bet");
        slots.cancelBet(betId);

        // Ensure we've not been credited a balance by some invariant
        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpotWad(), 333333333333333333);
    }

    function testCancelBetInvalidUser() public {
        uint256 bet = 1 * (10 ** 18);
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);

        // Ensure our bet has been added to the slots correctly
        assertEq(address(slots).balance, bet);

        // Attempt to cancel our bet with a different address
        vm.expectRevert("Invalid session requested for user");
        vm.prank(address(0));
        slots.cancelBet(betId);

        // Fulfill the bet
        vrf.fulfill(MAX_INT, betId);

        // Ensure we've not been charged for the VRF Fulfillment and have
        // successfully been reimbursed
        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpotWad(), 333333333333333333);
    }

    // Simulate a situation in which the VRF returns an old session ID for a user
    function testPlaceBetInvalidSessionId() public {
        uint256 bet = 1 * (10 ** 18);

        // Immediately place and cancel our bet
        uint256 betId = slots.placeBet{value: bet}(bet, WINLINE_STUB);
        slots.cancelBet(betId);

        // Place another bet, simulate a theoretical scenario in which the VRF
        // returns for a previous session
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(MAX_INT, betId);

        // We still have an active bet, so verify that our deposit is still there
        assertEq(address(this).balance, 100 * (10 ** 18) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpotWad(), 0);

        // Valid VRF fulfillment for the current user's bet:requestId
        vrf.fulfill(MAX_INT, vrf.requestId());

        // Jackpot has now been taken, successful
        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpotWad(), 333333333333333333);
    }

    function testFulfillCancelReentrancy() public {
        uint256 bet = 1 * (10 ** 18);
        // Setup our reentrancy contract. The contract attempts to call
        // cancelBet on the contract during the bet payout stage
        MockSlotsCancelReentrancy maliciousContract = new MockSlotsCancelReentrancy();
        deal(address(maliciousContract), 100 * (10 ** 18));

        // Set the caller address for this function invocation to be the
        // malicious contracts, as if the contract were calling to place a bet
        vm.prank(address(maliciousContract));
        // 1023 winline is a winning line for the board we've generated
        uint256 betId = slots.placeBet{value: bet}(bet, 1023);
        // Setup the malicious contract to attempt to cancel our betId with reentrancy
        maliciousContract.setBetId(betId);

        // Ensure that the VRF Callback fails, due to reentrancy
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(MAX_INT, betId);

        // Ensure the user, even though they're malicious, still have their bet active,
        // so it can still be withdrawn at a later date if need be. Ensure jackpot has not
        // been incremented
        assertEq(address(maliciousContract).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpotWad(), 0);
    }
}