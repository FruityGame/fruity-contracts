// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/Slots2.sol";
import "test/mocks/MockChainlinkVRF.sol";
import "test/mocks/MockFruityERC20.sol";

contract SlotsTest is Test {
    // 01|01|10|10|01
    uint256 constant WINLINE_STUB = 361;
    uint256 constant internal MAX_INT = 2**256 - 1;
    MockFruityERC20 fruity;
    MockChainlinkVRF vrf;
    BasicVideoSlots slots;

    function setUp() public virtual {
        fruity = new MockFruityERC20();
        vrf = new MockChainlinkVRF();
        slots = new BasicVideoSlots(
            address(vrf),
            address(0),
            bytes32(0),
            0,
            address(fruity)
        );
    }

    function testPlaceBet() public {
        slots.placeBet(10, WINLINE_STUB);
        vrf.fulfill(MAX_INT);
    }
}