// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockChainlinkVRF } from "test/mocks/MockChainlinkVRF.sol";

import { ChainlinkConsumer } from "src/randomness/consumer/Chainlink.sol";
import { GamesPool } from "src/GamesPool.sol";
import { Fruity } from "src/games/slots/machines/Fruity.sol";
import { Governance } from "src/governance/Governance.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";
import { ExternalPaymentProcessor } from "src/payment/proxy/ExternalPaymentProcessor.sol";

contract GamesPoolTest is Test {
    GamesPool gamesPool;
    Fruity game;

    MockERC20 token;
    MockChainlinkVRF vrf;

    address us;
    address user1 = address(0xDEADBEEF);
    address user2 = address(0xF00FD00F);

    receive() external payable {}
    fallback() external payable {}

    function setUp() public virtual {
        token = new MockERC20(0);
        vrf = new MockChainlinkVRF();

        gamesPool = new GamesPool(
            Governance.ExternalParams(
                250e18,
                Governance.InternalParams(10, 20, 50, 33, 40, 66, 10, 1000e18)
            ),
            ERC20VaultPaymentProcessor.VaultParams(token, "Fruity Governance", "vFRT")
        );

        game = new Fruity(
            ChainlinkConsumer.VRFParams(address(vrf), address(0), bytes32(0), uint64(0)),
            gamesPool
        );

        us = address(this);

        // Setup user balances
        token.mintExternal(us, 1000e18);
        token.mintExternal(user1, 500e18);
        token.mintExternal(user2, 500e18);
    }

    function testAddGame() public {
        Governance.InternalParams memory govParams = gamesPool.getParams().internalParams;
        // Approve the gamesPool to take our deposit
        token.approve(address(gamesPool), token.balanceOf(us));
        uint256 ourShares = gamesPool.deposit(token.balanceOf(us), us);

        // Create a governance proposal to add a game
        address[] memory targets = new address[](1);
        targets[0] = address(gamesPool);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            GamesPool.addGame.selector,
            address(game)
        );

        // Roll beyond minDurationHeld so our balance is factored into quorum()
        vm.roll(govParams.minDurationHeld + 1);

        // Create a proposal with sufficient deposit (will be immediately Active)
        uint256 proposalId = gamesPool.proposeWithDeposit(
            targets,
            values,
            calldatas,
            "Add Game",
            false,
            govParams.depositRequirement
        );

        // Roll forward to voting period
        vm.roll(block.number + 1);

        // Vote yes
        gamesPool.castVote(proposalId, uint8(Governance.Vote.Yes));

        // Roll forward to end voting period
        vm.roll(block.number + govParams.votingPeriod + 1);

        // Execute the governance proposal
        gamesPool.execute(targets, values, calldatas, keccak256("Add Game"));

        // Give ourselves a few more tokens to play with
        token.mintExternal(us, 1e18);
        token.approve(address(gamesPool), 1e18);

        // Attempt to place a bet with the game smart contract
        game.placeBet(1, 341);
    }

    function testAddGameUnauthorized() public {
        vm.expectRevert("Permission denied");
        gamesPool.addGame(address(game));

        vm.expectRevert("UNAUTHORIZED");
        game.placeBet(1, 341);
    }

    function testExecuteInvalidFunction() public {
        Governance.ExternalParams memory govParams = gamesPool.getParams();
        // Approve the gamesPool to take our deposit
        token.approve(address(gamesPool), token.balanceOf(us));
        uint256 ourShares = gamesPool.deposit(token.balanceOf(us), us);

        // Create a governance proposal to add a game
        address[] memory targets = new address[](1);
        targets[0] = address(gamesPool);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            GamesPool.addGame.selector,
            address(game)
        );
    }
}