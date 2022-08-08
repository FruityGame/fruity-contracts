// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/slots/games/Fruity.sol";

import "test/mocks/MockChainlinkVRF.sol";
import "test/mocks/MockERC20.sol";

contract FruityTest is Test {
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(1024))));

    MockChainlinkVRF vrf;
    MockERC20 token;
    Fruity fruity;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        vrf = new MockChainlinkVRF();
        token = new MockERC20(100e18);
        fruity = new Fruity(
            address(token), "FRUITY VAULT", "FRTV",
            ChainlinkConsumer.VRFParams(address(vrf), address(0), bytes32(0), uint64(0))
        );

        token.approve(address(fruity), 10e18);
    }

    function testPlaceBet() public {
        fruity.placeBet(1, 536169616821538800036600934927570202961204380927034107000682);
    }

    function testFulfillBet() public {
        uint256 betId = fruity.placeBet(1, 536169616821538800036600934927570202961204380927034107000682);

        emit log_uint(fruity.availableAssets());

        vrf.fulfill(
            betId,
            WINNING_ENTROPY
        );

        emit log_uint(token.balanceOf(address(this)));
        emit log_uint(token.balanceOf(address(fruity)));
    }
}