// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import "src/games/slots/BaseSlots.sol";
import "src/payment/NativePaymentProcessor.sol";

import { MockNativeCancelReentrancy } from "test/mocks/games/slots/reentrancy/MockNativeReentrancy.sol";
import { MockNativeIntegration } from "test/mocks/games/slots/reentrancy/MockNativeIntegration.sol";

contract NativeReentrancyTest is Test {
    uint256 constant ENTROPY = uint256(keccak256(abi.encodePacked(uint256(256))));
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(12345))));

    MockNativeCancelReentrancy maliciousContract;
    MockNativeIntegration slots;

    SlotParams slotParams;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        maliciousContract = new MockNativeCancelReentrancy();
        slots = new MockNativeIntegration(
            SlotParams(3, 5, 6, 255, 255, 255, 105, 0, 5, 500, 1e18),
            address(this)
        );

        deal(address(maliciousContract), 100e18);
        deal(address(slots), 100e18);

        slotParams = slots.getParams();
    }

    // Sorry these tests are so fragile
    function testFulfillCancelReentrancy() public {
        vm.prank(address(maliciousContract));
        uint256 betId = slots.placeBet{value: slotParams.creditSizeWad}(1);

        // Setup the malicious contract to attempt to cancel our betId with reentrancy
        maliciousContract.setBetId(betId);

        // Ensure that the VRF Callback fails, due to attempting to cancel a finished session
        vm.expectRevert(
            abi.encodeWithSelector(
                NativePaymentProcessor.PaymentError.selector,
                address(maliciousContract),
                6e18
            )
        );
        slots.fulfillRandomnessExternal(betId, 0);

        // Ensure the user, even though they're malicious, still have their bet active,
        // so it can still be withdrawn at a later date if need be. Ensure jackpot has not
        // been incremented
        assertEq(address(maliciousContract).balance, 100e18 - slotParams.creditSizeWad);
        assertEq(address(slots).balance, 100e18 + slotParams.creditSizeWad);
        assertEq(slots.jackpotWad(), 0);
    }

    function testCancelReentrancy() public {
        vm.prank(address(maliciousContract));
        uint256 betId = slots.placeBet{value: slotParams.creditSizeWad}(1);

        // Setup the malicious contract to attempt to cancel our betId with reentrancy
        maliciousContract.setBetId(betId);

        // Attempt to cancel the bet, starting the reentrancy attack
        vm.expectRevert(
            abi.encodeWithSelector(
                NativePaymentProcessor.PaymentError.selector,
                address(maliciousContract),
                1e18
            )
        );
        vm.prank(address(maliciousContract));
        slots.cancelBet(betId);

        // Ensure the user, even though they're malicious, still have their bet active,
        // so it can still be withdrawn at a later date if need be. Ensure jackpot has not
        // been incremented
        assertEq(address(maliciousContract).balance, 100e18 - slotParams.creditSizeWad);
        assertEq(address(slots).balance, 100e18 + slotParams.creditSizeWad);
        assertEq(slots.jackpotWad(), 0);
    }
}