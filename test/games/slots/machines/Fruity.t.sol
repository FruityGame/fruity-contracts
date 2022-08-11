// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "src/games/slots/BaseSlots.sol";
import "src/games/slots/machines/Fruity.sol";
import "src/payment/vault/ERC20VaultPaymentProcessor.sol";

import "test/mocks/MockChainlinkVRF.sol";
import "test/mocks/MockERC20.sol";

contract FruityTest is Test {
    uint256 constant ENTROPY = uint256(keccak256(abi.encodePacked(uint256(256))));
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(1024))));

    uint256 constant MAIN_WINLINE = 341;
    uint256 constant ALL_WINLINES = 536169616821538800036600934927570202961204380927034107000682;

    MockChainlinkVRF vrf;
    MockERC20 token;
    Fruity fruity;

    SlotParams fruityParams;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        vrf = new MockChainlinkVRF();
        token = new MockERC20(100e18);
        fruity = new Fruity(
            ERC20VaultPaymentProcessor.VaultParams(token, "Fruity Shares", "vFRTY"),
            ChainlinkConsumer.VRFParams(address(vrf), address(0), bytes32(0), uint64(0)),
            address(this)
        );

        fruityParams = fruity.getParams();
        token.approve(address(fruity), 10e18);
    }

    function testCancelInvalidBetId() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSlots.InvalidSession.selector,
                address(this),
                2
            )
        );
        fruity.cancelBet(2);
    }

    function testCancelBetAlreadyFulfilled() public {
        uint256 betId = fruity.placeBet(1, MAIN_WINLINE);
        vrf.fulfill(betId, ENTROPY);

        assertEq(token.balanceOf(address(this)), 100e18 - fruityParams.creditSizeWad);
        assertEq(token.balanceOf(address(fruity)), fruityParams.creditSizeWad);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSlots.InvalidSession.selector,
                address(this),
                betId
            )
        );
        fruity.cancelBet(betId);
    }

    function testFulfillBetAlreadyCancelled() public {
        uint256 betId = fruity.placeBet(1, MAIN_WINLINE);
        fruity.cancelBet(betId);

        vm.expectRevert("VRF Callback failed");
        vrf.fulfill(betId, ENTROPY);

        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.balanceOf(address(fruity)), 0);
    }
}