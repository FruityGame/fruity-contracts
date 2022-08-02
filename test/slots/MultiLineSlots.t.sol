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
    uint256 constant SLOTS_FUNDS = 100 * 1e18;

    uint32 constant WILDCARD = 4;
    uint32 constant SCATTER = 5;

    MockChainlinkVRF vrf;
    MockMuliLineSlots slots;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        vrf = new MockChainlinkVRF();
        slots = new MockMuliLineSlots(
            SlotParams(3, 5, 6, WILDCARD, SCATTER, 255, 115, 20, 5, 1e18),
            VRFParams(address(vrf), address(0), bytes32(0), 0),
            mockWinlines()
        );

        deal(address(this), SLOTS_FUNDS);
        deal(address(slots), SLOTS_FUNDS);
    }

    function testCheckWinline() public {
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(BOARD, WINLINE);
        assertEq(symbol1, 1);
        assertEq(count1, 1);

        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(BOARD, WINLINE_WINNER);
        assertEq(symbol2, 1);
        assertEq(count2, 5);
    }

    function testCheckWinlineWithWildcard() public {
        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
        uint256 boardWithWildcard = 1125917103554561;
        (uint256 symbol1, uint256 count1) = slots.checkWinlineExternal(boardWithWildcard, WINLINE);
        assertEq(symbol1, 1);
        assertEq(count1, 1);

        (uint256 symbol2, uint256 count2) = slots.checkWinlineExternal(boardWithWildcard, WINLINE_WINNER);
        assertEq(symbol2, 1);
        assertEq(count2, 5);

        // 2:[0000|0000|0100|0000|0000] 1:[0000|0000|0000|0001|0000] 0:[0001|0000|0000|0100|0001]
        uint256 boardWithWildcardSplit = 1125899923685441;
        (uint256 symbol3, uint256 count3) = slots.checkWinlineExternal(boardWithWildcardSplit, WINLINE);
        assertEq(symbol3, 1);
        assertEq(count3, 2);

        (uint256 symbol4, uint256 count4) = slots.checkWinlineExternal(boardWithWildcardSplit, WINLINE_WINNER);
        assertEq(symbol4, 1);
        assertEq(count4, 3);
    }

    function testCheckWinlineWithScatterStart() public {
        // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0000|0101]
        uint256 boardWithScatterStart = 281479288520709;
        (uint256 symbol, uint256 count) = slots.checkWinlineExternal(boardWithScatterStart, WINLINE);
        assertEq(symbol, 0);
        assertEq(count, 0);
    }

    function testCountWinlines() public {
        // Count 20 unique winlines for 5x5 slots
        assertEq(slots.countWinlinesExternal(WINLINES_FULL), 20);
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

    function testCheckScatter() public {
        assertEq(slots.checkScatterExternal(BOARD), 0);

        // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0101|0001]
        uint256 boardWithScatter = 281479288520785;
        assertEq(slots.checkScatterExternal(boardWithScatter), 1);

        // 2:[0101|0101|0101|0101|0101] 1:[0101|0101|0101|0101|0101] 0:[0101|0101|0101|0101|0101]
        uint256 boardFullScatter = 384307168202282325;
        assertEq(slots.checkScatterExternal(boardFullScatter), 15);
    }

    function testPlaceBet() public {
        uint256 betId = slots.placeBet{value: 1e18}(1, WINLINE);
        vrf.fulfill(betId, WINNING_ENTROPY);

        // Ensure our bet has been taken and the jackpot incremented
        assertEq(address(this).balance, SLOTS_FUNDS - 1e18);
        assertEq(address(slots).balance, SLOTS_FUNDS + 1e18);
        // In WEI, should equal 0.333333333333333333 Token
        assertEq(slots.jackpotWad(), 1e16);
    }

    function testPlaceBetInsufficientFunds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentProcessor.InsufficientFunds.selector,
                address(this), uint256(1e18), uint256(20 * 1e18)
            )
        );
        uint256 betId = slots.placeBet{value: 1e18}(1, WINLINES_FULL);

        // Ensure we've not been accredited any undue balances
        assertEq(address(this).balance, SLOTS_FUNDS);
        assertEq(address(slots).balance, SLOTS_FUNDS);
        assertEq(slots.jackpotWad(), 0);

        vm.expectRevert(abi.encodeWithSelector(BaseSlots.InvalidSession.selector, address(0), 0));
        slots.fulfillRandomnessExternal(betId, WINNING_ENTROPY);
    }

    function mockWinlines() private pure returns (uint256[] memory out) {
        out = new uint256[](20);
        out[0] = 341; out[1] = 682; out[2] = 1023; out[3] = 630; out[4] = 871;
        out[5] = 986; out[6] = 671; out[7] = 473; out[8] = 413; out[9] = 854;
        out[10] = 599; out[11] = 873; out[12] = 637; out[13] = 869; out[14] = 629;
        out[15] = 474; out[16] = 415; out[17] = 985; out[18] = 669; out[19] = 874;
    }
}