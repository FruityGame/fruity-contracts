// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";

import { Board } from "src/libraries/Board.sol";
import { SlotParams, BaseSlots } from "src/games/slots/BaseSlots.sol";
import { ChainlinkConsumer } from "src/randomness/consumer/Chainlink.sol";
import { Fruity } from "src/games/slots/machines/Fruity.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";

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
        token.approve(address(fruity), 100e18);
    }

    function testPlaceBetAllWinlines() public {
        // 20 Unique Winlines
        fruity.placeBet(1, 536169616821538800036600934927570202961204380927034107000682);

        assertEq(token.balanceOf(address(this)), 100e18 - (20 * fruityParams.creditSizeWad));
        assertEq(token.balanceOf(address(fruity)), 20 * fruityParams.creditSizeWad);
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

    /*function testSymbolRate() public {
        bytes32 seed = keccak256(abi.encode(0xD00DF00DA55));
        SlotParams memory _fruityParams = fruityParams;

        uint256 boardSize = _fruityParams.rows * _fruityParams.reels;
        uint256[] memory results = new uint256[](_fruityParams.symbols + 1);

        for (uint256 i = 0; i < 1000; i++) {
            uint256 randomness = uint256(keccak256(abi.encode(seed, i)));
            uint256 board = Board.generate(randomness, _fruityParams);

            for (uint256 j = 0; j < boardSize; j++) {
                results[Board.get(board, j)] += 1;
            }
        }

        for (uint256 k = 0; k < results.length; k++) {
            emit log_uint(results[k]);
        }
    }

    function testPayoutRate() public {
        bytes32 seed = keccak256(abi.encode(0xABCDEF123456));
        // Give 100 Token to the slot machine
        token.mintExternal(address(fruity), 100e18);

        for (uint256 i = 0; i < 1000; i++) {
            uint256 randomness = uint256(keccak256(abi.encode(seed, i)));
            uint256 betId = fruity.placeBet(5, ALL_WINLINES);
            vrf.fulfill(betId, randomness);
        }

        emit log_uint(token.balanceOf(address(this)) / 1e18);
        emit log_uint(token.balanceOf(address(fruity)) / 1e18);
    }*/
}