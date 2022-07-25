// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/libraries/Board.sol";
import "test/harnesses/SlotsTestHarness.sol";
import "test/mocks/MockChainlinkVRF.sol";

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
        vm.expectRevert("Invalid number parsed from board for this contract");
        slots.checkWinlineExternal(MAX_INT, WINLINE_STUB);
    }

    function testPlaceBet() public {
        uint256 bet = 1 * (10 ** 18);
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(MAX_INT);

        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        // In WEI, should equal 0.333333333333333333 Ether
        assertEq(slots.jackpot(), 333333333333333333);
    }

    function testPlaceBetInvalidAmount() public {
        uint256 bet = 1 * (10 ** 18);
        // Pass in two winlines
        vm.expectRevert("Amount provided not enough to cover bet");
        slots.placeBet{value: bet}(bet, 349801);
        vrf.fulfill(MAX_INT);

        assertEq(address(this).balance, 100 * (10 ** 18));
        assertEq(address(slots).balance, 0);
        assertEq(slots.jackpot(), 0);
    }

    function testPlaceBetInvalidIntoValid() public {
        uint256 bet = 1 * (10 ** 18);
        // Pass in two winlines
        vm.expectRevert("Amount provided not enough to cover bet");
        slots.placeBet{value: bet}(bet, 349801);
        vrf.fulfill(MAX_INT);

        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(MAX_INT);

        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpot(), 333333333333333333);
    }

    function testPlaceBetAlreadyActiveBet() public {
        uint256 bet = 1 * (10 ** 18);
        slots.placeBet{value: bet}(bet, WINLINE_STUB);

        vm.expectRevert("User already has a bet active");
        slots.placeBet{value: bet}(bet, WINLINE_STUB);

        vrf.fulfill(MAX_INT);

        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpot(), 333333333333333333);
    }

    function testWithdrawBet() public {
        uint256 bet = 1 * (10 ** 18);
        slots.placeBet{value: bet}(bet, WINLINE_STUB);

        assertEq(address(slots).balance, bet);

        slots.withdrawBet();

        // In a real world scenario, the chainlink VRF callback would fail to resolve
        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(MAX_INT);

        assertEq(address(this).balance, 100 * (10 ** 18));
        assertEq(address(slots).balance, 0);
        assertEq(slots.jackpot(), 0);
    }

    function testWithdrawBetNoActiveBet() public {
        uint256 bet = 1 * (10 ** 18);
        slots.placeBet{value: bet}(bet, WINLINE_STUB);
        vrf.fulfill(MAX_INT);

        vm.expectRevert("No bet active for user");
        slots.withdrawBet();

        assertEq(address(this).balance, (100 * (10 ** 18)) - bet);
        assertEq(address(slots).balance, bet);
        assertEq(slots.jackpot(), 333333333333333333);
    }
}