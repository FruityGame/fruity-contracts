// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import { IGovernor } from "src/governance/IGovernor.sol";
import { Governance } from "src/governance/Governance.sol";
import { MockGovernance } from "test/mocks/governance/MockGovernance.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

contract GovernanceTest is Test {
    using FixedPointMathLib for uint256;

    MockGovernance governance;
    MockERC20 token;

    uint256 constant minProposalDeposit = 10e18;
    Governance.Params governanceParams;

    ProposalHelper mockProposal;

    struct ProposalHelper {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
    }

    /*
        Test events
    */
    event ProposalCreated(
        uint256 proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint8 status,
        uint248 statusStartBlock,
        string description
    );

    event ProposalStatusChanged(uint256 indexed proposalId, uint8 oldStatus, uint8 newStatus);

    event VoteChanged(address indexed voter, uint256 indexed proposalId, uint8 previousVote, uint8 newVote);
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 vote, uint256 weight, string reason);

    event DepositReceived(address indexed depositor, uint256 indexed proposalId, uint256 amount);
    event DepositClaimed(address indexed depositor, uint256 indexed proposalId, uint256 amount);

    function setUp() public virtual {
        token = new MockERC20(0);
        // depositPeriodEnd, votePeriodEnd, yesThreshold, noWithVetoThreshold, quorumThreshold, requiredDeposit
        governanceParams = Governance.Params(10, 20, 50, 33, 40, minProposalDeposit * 2);
        governance = new MockGovernance(
            minProposalDeposit,
            governanceParams,
            token, "Mock Governance", "MGT"
        );

        bytes memory _calldata = abi.encodeWithSelector(
            MockERC20.mintExternal.selector,
            address(this),
            1e18
        );

        mockProposal = generateGovernanceProp(
            address(token),
            0,
            _calldata,
            "Hello, World!"
        );
    }

    function generateGovernanceProp(
        address target,
        uint256 value,
        bytes memory _calldata,
        string memory description
    ) internal pure
    returns (ProposalHelper memory) {
        address[] memory targets = new address[](1);
        targets[0] = target;

        uint256[] memory values = new uint256[](1);
        values[0] = value;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = _calldata;

        bytes32 descriptionHash = keccak256(bytes(description));

        return ProposalHelper(targets, values, calldatas, descriptionHash);
    }

    function testHashProposal() public {
        bytes memory _calldata = abi.encodeWithSelector(
            MockERC20.mintExternal.selector,
            address(this),
            1e18
        );

        ProposalHelper memory proposalOne = generateGovernanceProp(
            address(token), // Target Contract
            0, // Ether Value
            _calldata,
            "Hello, World!"
        );

        ProposalHelper memory proposalTwo = generateGovernanceProp(
            address(token),
            0,
            _calldata,
            "Hello, World"
        );

        uint256 proposalOneId = governance.hashProposal(
            proposalOne.targets,
            proposalOne.values,
            proposalOne.calldatas,
            proposalOne.descriptionHash
        );

        uint256 proposalTwoId = governance.hashProposal(
            proposalTwo.targets,
            proposalTwo.values,
            proposalTwo.calldatas,
            proposalTwo.descriptionHash
        );

        assert(proposalOneId != proposalTwoId);
    }

    function testQuorumReached() public {
        // Create a proposal with ID 0
        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Voting),
            governanceParams.depositRequirement,
            governanceParams
        );

        // Set total supply. As per parameters in setup hook, requires
        // > 40% (4e18) in the case of 10e18 total supply
        governance.pushTotalSupplyCheckpoint(10e18);

        // Roll forward to Voting Period Start
        vm.roll(block.number + 1);

        // No votes
        assertEq(governance.quorum(0), false);

        // 40%, should not be quorum
        governance.setVotes(0, [uint256(1e18), uint256(1e18), uint256(1e18), uint256(1e18)]);
        assertEq(governance.quorum(0), false);

        // 41%, should be quorum
        governance.setVotes(0, [uint256(1e18), uint256(1e18), uint256(1e18), uint256(1.1e18)]);
        assertEq(governance.quorum(0), true);
    }

    function testStateInvalidProposal() public {
        vm.expectRevert("Invalid Proposal");
        governance.state(0);

        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Deposit),
            governanceParams.depositRequirement,
            governanceParams
        );

        governance.state(0);

        vm.expectRevert("Invalid Proposal");
        governance.state(1);
    }

    function testStateLifecycle() public {
        uint256 depositRequirement = governanceParams.depositRequirement;
        uint256 startBlock = 1;

        // Setup a proposal in the Deposit (default) state
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Deposit),
            depositRequirement,
            governanceParams
        );

        // Setup totalSupply as propose() does
        governance.pushTotalSupplyCheckpoint(10e18);

        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Deposit));

        // Move forward beyond the Deposit Period end
        vm.roll(startBlock + governanceParams.depositPeriod + 1);

        // Insufficient deposit received
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Expired));

        // Set the proposal to be in state Voting (as per propose()/depositIntoProposal())
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Voting),
            depositRequirement,
            governanceParams
        );

        // No votes, but in Voting Period
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Voting));

        // Move forward beyond the Voting Period end (because the tally is only ever computed
        // at the end of the voting period)
        vm.roll(startBlock + governanceParams.votingPeriod + 1);

        // No quorum/votes received at end of voting period, Proposal Failed
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Failed));

        // Order is: [no, yes, abstain, noWithVeto]
        // Set the # of Yes votes to be greater than the Yes threshold (> 50% of tally)
        governance.setVotes(0, [uint256(3e18), uint256(5e18), uint256(2e18), uint256(0)]);
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Passed));

        // Set the # of Yes votes to be 50%
        governance.setVotes(0, [uint256(5e18), uint256(5e18), uint256(0), uint256(0)]);
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Rejected));

        // Set the # of NoWithVeto votes to be greater than the NoWithVeto threshold, but with with Abstains
        governance.setVotes(0, [uint256(1.6e18), uint256(2e18), uint256(5e18), uint256(3.3e18)]);
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Rejected));

        // Set the # of NoWithVeto votes to be greater than the NoWithVeto threshold
        governance.setVotes(0, [uint256(1e18), uint256(2e18), uint256(2e18), uint256(3.3e18)]);
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.RejectedWithVeto));

        // Set to Executed
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Executed),
            depositRequirement,
            governanceParams
        );

        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Executed));

        // Set to Failed (Execution Failed)
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Failed),
            depositRequirement,
            governanceParams
        );

        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Failed));
    }

    function testGetVote() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), 1e18);
        token.approve(address(governance), 1e18);
        governance.deposit(1e18, address(this));

        // Roll forward to ensure we can read the snapshot
        vm.roll(block.number + 1);

        assertEq(governance.getVotes(address(this), 1), governance.balanceOf(address(this)));
    }

    function testCastVote() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), 1e18);
        token.approve(address(governance), 1e18);
        governance.deposit(1e18, address(this));

        uint256 voteShares = governance.balanceOf(address(this));

        // Setup proposal with ID 0
        governance.setProposal(
            0,
            1,
            uint8(IGovernor.ProposalState.Voting),
            governanceParams.depositRequirement,
            governanceParams
        );

        // Increase total supply so our vote doesn't immediately pass the proposal
        governance.pushTotalSupplyCheckpoint(10e18);

        // Roll forward to voting period (deposit is active)
        vm.roll(2);

        uint8 yesVote = uint8(Governance.VoteType.Yes);

        // Vote yes
        vm.expectEmit(true, false, false, true);
        emit VoteCast(address(this), 0, yesVote, voteShares, "");
        governance.castVote(0, yesVote);

        assertEq(governance.getTallyFor(0, yesVote), voteShares);
        assert(governance.hasVoted(0, address(this)));

        // Attempt to vote yes again
        vm.expectRevert("Vote already cast");
        governance.castVote(0, yesVote);
    }

    function testCastVoteInvalidVote() public {
        // Setup proposal with ID 0
        governance.setProposal(
            0,
            1,
            uint8(IGovernor.ProposalState.Voting),
            governanceParams.depositRequirement,
            governanceParams
        );

        // Roll forward to voting period (deposit is active)
        vm.roll(2);

        vm.expectRevert("Invalid Vote");
        governance.castVote(0, type(uint8).max);

        vm.expectRevert("Invalid Vote");
        governance.castVote(0, 0);
    }

    function testCastVoteChangeVote() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), 1e18);
        token.approve(address(governance), 1e18);
        governance.deposit(1e18, address(this));

        uint256 voteShares = governance.balanceOf(address(this));

        // Setup proposal with ID 0
        governance.setProposal(
            0,
            1,
            uint8(IGovernor.ProposalState.Voting),
            governanceParams.depositRequirement,
            governanceParams
        );

        // Increase total supply so our vote doesn't immediately pass the proposal
        governance.pushTotalSupplyCheckpoint(10e18);

        // Roll forward to voting period (deposit is active)
        vm.roll(2);

        uint8 yesVote = uint8(Governance.VoteType.Yes);
        uint8 noVote = uint8(Governance.VoteType.No);

        // Vote yes
        governance.castVote(0, yesVote);

        assertEq(governance.getTallyFor(0, yesVote), voteShares);
        assert(governance.hasVoted(0, address(this)));

        // Vote no
        vm.expectEmit(true, false, false, true);
        emit VoteCast(address(this), 0, noVote, voteShares, "Hello, World!");
        emit VoteChanged(address(this), 0, yesVote, noVote);
        governance.castVoteWithReason(0, noVote, "Hello, World!");

        assertEq(governance.getTallyFor(0, yesVote), 0);
        assertEq(governance.getTallyFor(0, noVote), voteShares);
        assert(governance.hasVoted(0, address(this)));
    }

    function testCastVoteInvalidProposal() public {
        vm.expectRevert("Invalid Proposal");
        governance.castVote(0, uint8(Governance.VoteType.Yes));
    }

    function testCastVoteInactiveProposal() public {
        // Setup proposal with ID 0
        governance.setProposal(
            0,
            1,
            uint8(IGovernor.ProposalState.Deposit),
            minProposalDeposit,
            governanceParams
        );

        // Roll forward to voting period (deposit period expired)
        vm.roll(2);

        vm.expectRevert("Proposal is not in Voting Period");
        governance.castVote(0, uint8(Governance.VoteType.Yes));

        // Roll forward to end of voting period
        vm.roll(governanceParams.votingPeriod + 1);

        vm.expectRevert("Proposal is not in Voting Period");
        governance.castVote(0, uint8(Governance.VoteType.Yes));
    }

    function testPropose() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), minProposalDeposit);
        token.approve(address(governance), minProposalDeposit);
        governance.deposit(minProposalDeposit, address(this));

        uint256 proposalId = governance.hashProposal(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            keccak256(bytes("Hello, World"))
        );

        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            proposalId,
            address(this),
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            uint8(IGovernor.ProposalState.Deposit),
            uint248(block.number),
            "Hello, World"
        );
        governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World"
        );

        assertEq(governance.getDeposit(proposalId, address(this)), minProposalDeposit);
        assertEq(governance.balanceOf(address(governance)), minProposalDeposit);
        assertEq(governance.balanceOf(address(this)), 0);
    }

    function testProposeWithDepositSufficientDeposit() public {
        uint256 deposit = governanceParams.depositRequirement;

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);
        governance.deposit(deposit, address(this));

        uint256 proposalId = governance.hashProposal(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            keccak256(bytes("Hello, World"))
        );

        // Ensure we're put straight into the voting phase
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            proposalId,
            address(this),
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            uint8(IGovernor.ProposalState.Voting),
            uint248(block.number),
            "Hello, World"
        );
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            deposit
        );

        assertEq(governance.getDeposit(proposalId, address(this)), deposit);
        assertEq(governance.balanceOf(address(governance)), deposit);
        assertEq(governance.balanceOf(address(this)), 0);

        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Voting));
    }

    function testProposeWithDepositInvalidDeposit() public {
        vm.expectRevert("Invalid Deposit");
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            0
        );

        assertEq(governance.balanceOf(address(governance)), 0);

        vm.expectRevert("Invalid Deposit");
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            minProposalDeposit - 1
        );

        assertEq(governance.balanceOf(address(governance)), 0);
    }

    function testProposeWithDepositEmptyProposal() public {
        address[] memory emptyTargets = new address[](0);
        uint256[] memory emptyValues = new uint256[](0);
        bytes[] memory emptyCalldatas = new bytes[](0);

        // Test with empty targets
        vm.expectRevert("Invalid Proposal");
        governance.proposeWithDeposit(
            emptyTargets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            minProposalDeposit
        );

        assertEq(governance.balanceOf(address(governance)), 0);

        // Test with empty values
        vm.expectRevert("Invalid Proposal");
        governance.proposeWithDeposit(
            mockProposal.targets,
            emptyValues,
            mockProposal.calldatas,
            "Hello, World",
            minProposalDeposit
        );

        assertEq(governance.balanceOf(address(governance)), 0);

        // Test with empty calldatas
        vm.expectRevert("Invalid Proposal");
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            emptyCalldatas,
            "Hello, World",
            minProposalDeposit
        );

        assertEq(governance.balanceOf(address(governance)), 0);

        // Test with all 3
        vm.expectRevert("Invalid Proposal");
        governance.proposeWithDeposit(
            emptyTargets,
            emptyValues,
            emptyCalldatas,
            "Hello, World",
            minProposalDeposit
        );

        assertEq(governance.balanceOf(address(governance)), 0);
    }

    function testProposeWithDepositInsufficientBalance() public {
        vm.expectRevert("Insufficient Vault Shares to make deposit");
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            minProposalDeposit
        );

        assertEq(governance.balanceOf(address(governance)), 0);
    }

    function testProposeDuplicateProposal() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), minProposalDeposit);
        token.approve(address(governance), minProposalDeposit);
        governance.deposit(minProposalDeposit, address(this));

        uint256 proposalId = governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World"
        );

        vm.expectRevert("Proposal already exists");
        governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World"
        );

        assertEq(governance.getDeposit(proposalId, address(this)), minProposalDeposit);
        assertEq(governance.balanceOf(address(governance)), minProposalDeposit);
        assertEq(governance.balanceOf(address(this)), 0);
    }

    function testDepositIntoProposal() public {
        address us = address(this);
        address them = address(0xDEADBEEF);

        // Setup our test users with some Vault Shares
        token.mintExternal(us, minProposalDeposit);
        token.mintExternal(them, minProposalDeposit);

        // Deposit our shares
        token.approve(address(governance), minProposalDeposit);
        governance.deposit(minProposalDeposit, us);

        // Deposit their shares
        vm.prank(them);
        token.approve(address(governance), minProposalDeposit);
        vm.prank(them);
        governance.deposit(minProposalDeposit, them);

        // Create a proposal as user (us)
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            minProposalDeposit
        );

        // Ensure that put us into the deposit period
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Deposit));

        // Roll forward 4 blocks
        vm.roll(5);

        // Deposit into proposal as them
        vm.prank(them);
        vm.expectEmit(true, false, false, true);
        emit DepositReceived(them, proposalId, minProposalDeposit);
        emit ProposalStatusChanged(proposalId, uint8(IGovernor.ProposalState.Deposit), uint8(IGovernor.ProposalState.Voting));
        governance.depositIntoProposal(proposalId, minProposalDeposit);

        // Move forward to voting period (Total Supply snapshot will be taken on block 5)
        vm.roll(6);

        // Should now be onto Voting stage
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Voting));

        assertEq(governance.getDeposit(proposalId, us), minProposalDeposit);
        assertEq(governance.getDeposit(proposalId, them), minProposalDeposit);
        assertEq(governance.balanceOf(address(governance)), governanceParams.depositRequirement);
        assertEq(governance.balanceOf(us), 0);
        assertEq(governance.balanceOf(them), 0);
    }

    function testDepositIntoProposalInvalidDeposit() public {
        // Setup test with enough tokens to make a deposit
        token.mintExternal(address(this), minProposalDeposit);
        token.approve(address(governance), minProposalDeposit);
        governance.deposit(minProposalDeposit, address(this));

        // Create a proposal
        uint256 proposalId = governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World"
        );

        // Attempt to deposit into the proposal with too small of a value
        vm.expectRevert("Invalid deposit");
        governance.depositIntoProposal(proposalId, 0);

        // Attempt to deposit into the proposal with an Insufficient Balance
        vm.expectRevert("Insufficient Vault Shares to make deposit");
        governance.depositIntoProposal(proposalId, 1);

        // Ensure still in Deposit period
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Deposit));
    }

    function testDepositIntoProposalInvalidProposal() public {
        vm.expectRevert("Invalid Proposal");
        governance.depositIntoProposal(0, 1);
    }

    function testDepositIntoProposalFundedProposal() public {
        uint256 deposit = governanceParams.depositRequirement;

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);
        governance.deposit(deposit, address(this));

        // Create a fully funded proposal
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            deposit
        );

        // Attempt to deposit again when we've gone beyond the Deposit stage
        vm.expectRevert("Proposal is not in Deposit stage");
        governance.depositIntoProposal(proposalId, 1);
    }

    function testClaimDeposit() public {
        address us = address(this);
        address them = address(0xDEADBEEF);

        // Setup our test users with some Vault Shares
        token.mintExternal(us, minProposalDeposit);
        token.mintExternal(them, minProposalDeposit);

        // Deposit our shares
        token.approve(address(governance), minProposalDeposit);
        governance.deposit(minProposalDeposit, us);

        // Deposit their shares
        vm.prank(them);
        token.approve(address(governance), minProposalDeposit);
        vm.prank(them);
        governance.deposit(minProposalDeposit, them);

        // Create a proposal as user (us)
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            minProposalDeposit
        );

        // Deposit as (them)
        vm.prank(them);
        governance.depositIntoProposal(proposalId, minProposalDeposit);

        // Roll forward a block to the voting stage
        vm.roll(2);

        // Mock a Yes vote majority
        governance.setVotes(proposalId, [0, minProposalDeposit * 2, 0, 0]);

        // Move to the end of the voting period
        vm.roll(governanceParams.votingPeriod + 2);

        // Claim our deposit
        vm.expectEmit(true, false, false, true);
        emit DepositClaimed(us, proposalId, minProposalDeposit);
        governance.claimDeposit(proposalId);

        assertEq(governance.getDeposit(proposalId, us), 0);
        assertEq(governance.getDeposit(proposalId, them), minProposalDeposit);
        assertEq(governance.balanceOf(address(governance)), minProposalDeposit);
        assertEq(governance.balanceOf(us), minProposalDeposit);
        assertEq(governance.balanceOf(them), 0);

        // Mock a NoWithVeto vote majority
        governance.setVotes(proposalId, [0, 0, 0, minProposalDeposit]);

        // Attempt to Claim their deposit with a NoWithVeto majority
        vm.prank(them);
        vm.expectRevert("Invalid claim request");
        governance.claimDeposit(proposalId);

        // Change back to a Yes vote majority
        governance.setVotes(proposalId, [0, minProposalDeposit * 2, 0, 0]);

        // Claim their deposit
        vm.prank(them);
        vm.expectEmit(true, false, false, true);
        emit DepositClaimed(them, proposalId, minProposalDeposit);
        governance.claimDeposit(proposalId);

        assertEq(governance.getDeposit(proposalId, us), 0);
        assertEq(governance.getDeposit(proposalId, them), 0);
        assertEq(governance.balanceOf(address(governance)), 0);
        assertEq(governance.balanceOf(us), minProposalDeposit);
        assertEq(governance.balanceOf(them), minProposalDeposit);

        // Attempt to double claim
        vm.expectRevert("Invalid claim request");
        governance.claimDeposit(proposalId);
    }

    function testClaimDepositInvalidProposal() public {
        vm.expectRevert("Invalid Proposal");
        governance.claimDeposit(0);
    }

    function testClaimDepositInvalidUser() public {
        uint256 deposit = governanceParams.depositRequirement;
        // Create a proposal with a sufficient deposit

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);
        governance.deposit(deposit, address(this));

        // Create a fully funded proposal
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [minProposalDeposit, 0, 0, 0]);

        // Attempt to claim as a different user
        vm.prank(address(0xDEADBEEF));
        vm.expectRevert("Invalid claim request");
        governance.claimDeposit(proposalId);
    }

    function testExecute() public {
        uint256 deposit = governanceParams.depositRequirement;
        Governance.Params memory newParams = Governance.Params(5, 20, 50, 33, 40, minProposalDeposit * 2);

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);
        governance.deposit(deposit, address(this));

        // Setup the function to call
        bytes memory _calldata = abi.encodeWithSelector(
            Governance.setParams.selector,
            newParams
        );
        ProposalHelper memory _proposal = generateGovernanceProp(address(governance), 0, _calldata, "Test Proposal");

        // Create a proposal with a sufficient deposit
        uint256 proposalId = governance.proposeWithDeposit(
            _proposal.targets,
            _proposal.values,
            _proposal.calldatas,
            "Test Proposal",
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [0, deposit, 0, 0]);

        // Move to the end of the voting period
        vm.roll(governanceParams.votingPeriod + 2);

        // Execute the function, expect a state change to `Executed`
        vm.expectEmit(true, false, false, true);
        emit ProposalStatusChanged(proposalId, uint8(IGovernor.ProposalState.Passed), uint8(IGovernor.ProposalState.Executed));
        governance.execute(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256("Test Proposal"));

        // Ensure the function has executed
        (uint32 newDepositPeriod,,,,,) = governance.params();
        assertEq(newDepositPeriod, newParams.depositPeriod);

        // Ensure status has been set and hooks called
        (,uint8 status,,) = governance.proposals(proposalId);
        assertEq(status, uint8(IGovernor.ProposalState.Executed));
        assertEq(governance.beforeExecuteCalls(), 1);
        assertEq(governance.afterExecuteCalls(), 1);
    }

    function testExecuteFailure() public {
        uint256 deposit = governanceParams.depositRequirement;
        Governance.Params memory newParams = Governance.Params(50, 75, 500, 500, 500, 0);

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);
        governance.deposit(deposit, address(this));

        // Setup the function to call with incorrect parameters
        bytes memory _calldata = abi.encodeWithSelector(
            Governance.setParams.selector,
            newParams
        );
        ProposalHelper memory _proposal = generateGovernanceProp(address(governance), 0, _calldata, "Test Proposal");

        // Create a proposal with a sufficient deposit
        uint256 proposalId = governance.proposeWithDeposit(
            _proposal.targets,
            _proposal.values,
            _proposal.calldatas,
            "Test Proposal",
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [0, deposit, 0, 0]);

        // Move to the end of the voting period
        vm.roll(governanceParams.votingPeriod + 2);

        // Execute the function, expect a state change to `Executed`
        vm.expectEmit(true, false, false, true);
        emit ProposalStatusChanged(proposalId, uint8(IGovernor.ProposalState.Passed), uint8(IGovernor.ProposalState.Failed));
        governance.execute(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256("Test Proposal"));

        // Ensure the function has not changed the state
        (uint32 depositPeriod,,,,,) = governance.params();
        assertEq(depositPeriod, governanceParams.depositPeriod);

        // Ensure status has been set and hooks called
        (,uint8 status,,) = governance.proposals(proposalId);
        assertEq(status, uint8(IGovernor.ProposalState.Failed));
        assertEq(governance.beforeExecuteCalls(), 1);
        assertEq(governance.afterExecuteCalls(), 1);
    }

    function testOnlyGovernance() public {
        // Attempt as test user
        vm.expectRevert("Permission denied");
        governance.setParams(governanceParams);

        // Attempt as Governance
        vm.prank(address(governance));
        governance.setParams(governanceParams);
    }
}