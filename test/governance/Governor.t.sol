// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { IGovernor } from "src/governance/IGovernor.sol";
import { Governor } from "src/governance/Governor.sol";

import { MockERC20Snapshot } from "test/mocks/tokens/MockERC20Snapshot.sol";
import { MockGovernor } from "test/mocks/governance/MockGovernor.sol";

import { Math } from "src/libraries/Math.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

contract GovernorTest is Test {
    using FixedPointMathLib for uint256;

    MockGovernor governance;
    MockERC20Snapshot token;

    Governor.ExternalParams governanceParams;

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
        uint240 statusStartBlock,
        bool urgent,
        string description
    );

    event ProposalStatusChanged(uint256 indexed proposalId, uint8 oldStatus, uint8 newStatus);

    event VoteChanged(address indexed voter, uint256 indexed proposalId, uint8 previousVote, uint8 newVote);
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 vote, uint256 weight, string reason);

    event DepositReceived(address indexed depositor, uint256 indexed proposalId, uint256 amount);
    event DepositClaimed(address indexed depositor, uint256 indexed proposalId, uint256 amount);
    event DepositBurned(address indexed burner, uint256 indexed proposalId, uint256 amount);

    function setUp() public virtual {
        token = new MockERC20Snapshot(0);

        // depositPeriodEnd, votePeriodEnd, yesThreshold, noWithVetoThreshold, quorumThreshold, requiredDeposit
        governanceParams = Governor.ExternalParams(
            10e18,
            Governor.InternalParams(10, 20, 50, 33, 40, 66, 1, 20e18)
        );
        governance = new MockGovernor(token, governanceParams);

        bytes memory _calldata = abi.encodeWithSelector(
            MockERC20Snapshot.mintExternal.selector,
            address(this),
            1e18
        );

        mockProposal = generateGovernorProp(
            address(token),
            0,
            _calldata,
            "Hello, World!"
        );
    }

    function generateGovernorProp(
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
            MockERC20Snapshot.mintExternal.selector,
            address(this),
            1e18
        );

        ProposalHelper memory proposalOne = generateGovernorProp(
            address(token), // Target Contract
            0, // Ether Value
            _calldata,
            "Hello, World!"
        );

        ProposalHelper memory proposalTwo = generateGovernorProp(
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
        // Set total supply. As per parameters in setup hook, requires
        // > 40% (4e18) in the case of 10e18 total supply
        token.pushTotalSupplyCheckpoint(10e18);
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Create a proposal with ID 0
        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

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
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, 0));
        governance.state(0);

        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Deposit),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        governance.state(0);

        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, 1));
        governance.state(1);
    }

    function testStateLifecycle() public {
        // Set total supply as propose() does.
        token.pushTotalSupplyCheckpoint(10e18);

        // Move forward to the minimumStakingDuration, ensuring the above
        // totalSupply snapshot is valid for this proposal
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        uint256 depositRequirement = governanceParams.internalParams.depositRequirement;
        uint256 startBlock = block.number;

        // Setup a proposal in the Deposit (default) state
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Deposit),
            false,
            depositRequirement,
            governanceParams.internalParams
        );

        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Deposit));

        // Move forward beyond the Deposit Period end
        vm.roll(startBlock + governanceParams.internalParams.depositPeriod + 1);

        // Insufficient deposit received
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Expired));

        // Set the proposal to be in state Voting, as if it were fully funded
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Voting),
            false,
            depositRequirement,
            governanceParams.internalParams
        );

        // No votes, but in Voting Period
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Voting));

        // Move forward beyond the Voting Period end (because the tally is only ever computed
        // at the end of the voting period)
        vm.roll(startBlock + governanceParams.internalParams.votingPeriod + 1);

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

        // Set to Executed (set in execute())
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Executed),
            false,
            depositRequirement,
            governanceParams.internalParams
        );

        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Executed));

        // Set to Failed (Execution Failed, set in execute())
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Failed),
            false,
            depositRequirement,
            governanceParams.internalParams
        );

        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Failed));
    }

    function testStateUrgent() public {
        // Set total supply as propose() does.
        token.pushTotalSupplyCheckpoint(10e18);

        // Move forward to the minimumStakingDuration, ensuring the above
        // totalSupply snapshot is valid for this proposal
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        uint256 depositRequirement = governanceParams.internalParams.depositRequirement;
        uint256 startBlock = block.number;

        // Setup an Urgent Proposal in the Voting state
        governance.setProposal(
            0,
            startBlock,
            uint8(IGovernor.ProposalState.Voting),
            true,
            depositRequirement,
            governanceParams.internalParams
        );

        // No votes, but in Voting Period
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Voting));

        // Set a yes supermajority, which should cause the proposal to immediately go to 'Passed', as it's Urgent
        governance.setVotes(0, [uint256(1e18), uint256(6.7e18), uint256(2e18), uint256(0.3e18)]);
        assertEq(uint8(governance.state(0)), uint8(IGovernor.ProposalState.Passed));

        // Roll forward to end of voting period
        vm.roll(startBlock + governanceParams.internalParams.votingPeriod + 1);

        // Ensure normal state/process flow can be reached if votes aren't sufficient

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
    }

    function testGetVote() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), 1e18);

        // Move forward a block to allow the Checkpoint to become valid
        vm.roll(2);

        assertEq(governance.getVotes(address(this), 1), token.balanceOf(address(this)));
    }

    function testProposalSnapshot() public {
        // Set the minDurationHeld to 10 blocks
        governanceParams.internalParams.minDurationHeld = 10;

        // Make a deposit at Block 1
        token.mintExternal(address(this), 1e18);

        // Create a proposal at block 5
        governance.setProposal(
            0,
            5,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        // Roll forward block 9 (valid Voting Period for Proposal)
        vm.roll(9);

        // Ensure the proposal snapshot is factoring in the minDurationHeld
        assertEq(governance.proposalSnapshot(0), 0);
    }

    function testCastVote() public {
        // Deposit shares at block 1
        token.mintExternal(address(this), 1e18);

        uint256 voteShares = token.balanceOf(address(this));

        // Increase total supply to simulate others' deposits, so
        // our vote doesn't cause the proposal to immediately pass for this test
        token.pushTotalSupplyCheckpoint(10e18);

        // Roll forward beyond the min staking duration to have
        // our shares become elegible for use in Voting
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Setup proposal with ID 0
        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        // Roll forward to voting period (deposit is active + beyond minDurationHeld)
        vm.roll(block.number + 1);

        uint8 yesVote = uint8(IGovernor.Vote.Yes);

        // Vote yes
        vm.expectEmit(true, false, false, true);
        emit VoteCast(address(this), 0, yesVote, voteShares, "");
        governance.castVote(0, yesVote);

        assertEq(governance.getTallyFor(0, yesVote), voteShares);
        assert(governance.hasVoted(0, address(this)));

        // Attempt to vote yes again
        vm.expectRevert(abi.encodeWithSelector(Governor.DuplicateVote.selector, address(this), yesVote));
        governance.castVote(0, yesVote);
    }

    function testCastVoteNoShares() public {
        token.pushTotalSupplyCheckpoint(10e18);

        // Roll forward beyond the min staking duration to have
        // our shares become elegible for use in Voting
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Setup proposal with ID 0
        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        // Ensure an appropriate error is thrown for the user to interpret
        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientVotes.selector, address(this)));
        governance.castVote(0, uint8(IGovernor.Vote.Yes));
    }

    function testCastVoteMinimumStakingDuration() public {
        // Set the minDurationHeld to 10 blocks
        uint256 minDurationHeld = (governanceParams.internalParams.minDurationHeld = 10);

        // Make our deposit on Block 1
        token.mintExternal(address(this), 1e18);

        // Move forward to just before the minDurationHeld
        vm.roll(minDurationHeld);

        // Setup proposal with ID 0 at block(minDurationHeld - 1)
        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        // Roll forward to voting period
        vm.roll(block.number + 1);

        // Attempt to vote yes, ensure our vote fails due to 0 shares
        // being considered because of minDurationHeld
        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientVotes.selector, address(this)));
        governance.castVote(0, uint8(IGovernor.Vote.Yes));
    }

    function testCastVoteInvalidVote() public {
        // Setup proposal with ID 0
        governance.setProposal(
            0,
            1,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        // Roll forward to voting period
        vm.roll(2);

        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidVote.selector, type(uint8).max));
        governance.castVote(0, type(uint8).max);

        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidVote.selector, 0));
        governance.castVote(0, 0);
    }

    function testCastVoteChangeVote() public {
        // Deposit shares at block 1
        token.mintExternal(address(this), 1e18);

        uint256 voteShares = token.balanceOf(address(this));

        // Increase total supply to simulate others' deposits, so
        // our vote doesn't cause the proposal to immediately pass for this test
        token.pushTotalSupplyCheckpoint(10e18);

        // Roll forward beyond the min staking duration to have our shares
        // become elegible for use in Voting
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Setup proposal with ID 0
        governance.setProposal(
            0,
            block.number,
            uint8(IGovernor.ProposalState.Voting),
            false,
            governanceParams.internalParams.depositRequirement,
            governanceParams.internalParams
        );

        // Roll forward to voting period
        vm.roll(block.number + 1);

        uint8 yesVote = uint8(IGovernor.Vote.Yes);
        uint8 noVote = uint8(IGovernor.Vote.No);

        // Vote yes
        governance.castVote(0, yesVote);

        assertEq(governance.getTallyFor(0, yesVote), voteShares);
        assert(governance.hasVoted(0, address(this)));

        // Vote no
        vm.expectEmit(true, false, false, true);
        emit VoteCast(address(this), 0, noVote, voteShares, "Hello, World!");
        emit VoteChanged(address(this), 0, yesVote, noVote);
        governance.castVoteWithReason(0, noVote, "Hello, World!");

        // Ensure tallies are correct
        assertEq(governance.getTallyFor(0, yesVote), 0);
        assertEq(governance.getTallyFor(0, noVote), voteShares);
        assert(governance.hasVoted(0, address(this)));
    }

    function testCastVoteInvalidProposal() public {
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, 0));
        governance.castVote(0, uint8(IGovernor.Vote.Yes));
    }

    function testCastVoteInactiveProposal() public {
        // Setup proposal with ID 0
        governance.setProposal(
            0,
            1,
            uint8(IGovernor.ProposalState.Deposit),
            false,
            governanceParams.minDepositRequirement,
            governanceParams.internalParams
        );

        // Roll forward to voting period (deposit period expired)
        vm.roll(2);

        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.Deposit)));
        governance.castVote(0, uint8(IGovernor.Vote.Yes));

        // Roll forward to end of voting period 
        vm.roll(block.number + governanceParams.internalParams.votingPeriod + 1);

        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.Expired)));
        governance.castVote(0, uint8(IGovernor.Vote.Yes));
    }

    function testPropose() public {
        // Deposit enough shares to create a proposal, but not activate it
        token.mintExternal(address(this), governanceParams.minDepositRequirement);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        uint256 proposalId = governance.hashProposal(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            keccak256(bytes("Hello, World"))
        );

        // Create a proposal
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(
            proposalId,
            address(this),
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            uint8(IGovernor.ProposalState.Deposit),
            uint240(block.number),
            false,
            "Hello, World"
        );
        governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false
        );

        // Ensure balances are correct
        assertEq(governance.getDeposit(proposalId, address(this)), governanceParams.minDepositRequirement);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(governance)), governanceParams.minDepositRequirement);
    }

    function testProposeWithDepositSufficientDeposit() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;

        // Deposit enough shares to both create and insantly activate a proposal
        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

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
            uint240(block.number),
            false,
            "Hello, World"
        );
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            deposit
        );

        assertEq(governance.getDeposit(proposalId, address(this)), deposit);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(governance)), deposit);

        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Voting));
    }

    function testProposeWithDepositUrgent() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;

        // Deposit enough shares to both create and insantly activate a proposal
        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

        // Roll forward beyond minDurationHeld so our balance is elegible for voting
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Ensure we're put straight into the voting phase and have been set as Urgent
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            true,
            deposit
        );

        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Voting));

        // Cast a Supermajority yes vote on our Urgent deposit
        governance.castVote(proposalId, uint8(IGovernor.Vote.Yes));

        // Ensure the proposal has been immediately marked as `Passed`
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Passed));

        // Ensure the vote cannot be changed after the fact
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.Passed)));
        governance.castVote(proposalId, uint8(IGovernor.Vote.No));
    }

    function testProposeWithDepositInvalidDeposit() public {
        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientDeposit.selector, 0));
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            0
        );

        assertEq(token.balanceOf(address(governance)), 0);

        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientDeposit.selector, governanceParams.minDepositRequirement - 1));
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement - 1
        );

        // Ensure our deposits haven't been received
        assertEq(token.balanceOf(address(governance)), 0);
    }

    function testProposeWithDepositInsufficientBalance() public {
        token.mintExternal(address(this), governanceParams.minDepositRequirement - 1);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        // Attempt to make a deposit > our deposited balance/shares
        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientBalance.selector, governanceParams.minDepositRequirement - 1));
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );
    }

    function testProposeWithDepositEmptyProposal() public {
        address[] memory emptyTargets = new address[](0);
        uint256[] memory emptyValues = new uint256[](0);
        bytes[] memory emptyCalldatas = new bytes[](0);

        uint256 emptyTargetId = governance.hashProposal(
            emptyTargets,
            mockProposal.values,
            mockProposal.calldatas,
            keccak256(bytes("Hello, World"))
        );
        // Test with empty targets
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, emptyTargetId));
        governance.proposeWithDeposit(
            emptyTargets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        assertEq(token.balanceOf(address(governance)), 0);

        uint256 emptyValuesId = governance.hashProposal(
            mockProposal.targets,
            emptyValues,
            mockProposal.calldatas,
            keccak256(bytes("Hello, World"))
        );
        // Test with empty values
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, emptyValuesId));
        governance.proposeWithDeposit(
            mockProposal.targets,
            emptyValues,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        assertEq(token.balanceOf(address(governance)), 0);

        uint256 emptyCalldatasId = governance.hashProposal(
            mockProposal.targets,
            mockProposal.values,
            emptyCalldatas,
            keccak256(bytes("Hello, World"))
        );
        // Test with empty calldatas
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, emptyCalldatasId));
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            emptyCalldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        assertEq(token.balanceOf(address(governance)), 0);

        uint256 allEmptyId = governance.hashProposal(
            emptyTargets,
            emptyValues,
            emptyCalldatas,
            keccak256(bytes("Hello, World"))
        );
        // Test with all 3
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, allEmptyId));
        governance.proposeWithDeposit(
            emptyTargets,
            emptyValues,
            emptyCalldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        assertEq(token.balanceOf(address(governance)), 0);
    }

    function testProposeWithDepositDuplicateProposal() public {
        // Setup our test with some Vault Shares
        token.mintExternal(address(this), governanceParams.minDepositRequirement);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, proposalId));
        governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );
    }

    function testDepositIntoProposal() public {
        address us = address(this);
        address them = address(0xDEADBEEF);

        // Setup our test users with some Vault Shares
        token.mintExternal(us, governanceParams.minDepositRequirement);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        token.mintExternal(them, governanceParams.minDepositRequirement);
        vm.prank(them);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        // Create a proposal as user (us)
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        // Ensure that put us into the deposit period
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Deposit));

        // Roll forward 4 blocks
        vm.roll(block.number + 4);

        // Deposit into proposal as them
        vm.prank(them);
        vm.expectEmit(true, false, false, true);
        emit DepositReceived(them, proposalId, governanceParams.minDepositRequirement);
        emit ProposalStatusChanged(proposalId, uint8(IGovernor.ProposalState.Deposit), uint8(IGovernor.ProposalState.Voting));
        governance.depositIntoProposal(proposalId, governanceParams.minDepositRequirement);

        // Move forward to voting period
        vm.roll(block.number + 1);

        // Should now be onto Voting stage
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Voting));

        // Ensure balances are correct
        assertEq(governance.getDeposit(proposalId, us), governanceParams.minDepositRequirement);
        assertEq(governance.getDeposit(proposalId, them), governanceParams.minDepositRequirement);
        assertEq(token.balanceOf(us), 0);
        assertEq(token.balanceOf(them), 0);
        assertEq(token.balanceOf(address(governance)), governanceParams.minDepositRequirement * 2);
    }

    function testDepositIntoProposalInvalidDeposit() public {
        // Setup test with enough tokens to make a deposit
        token.mintExternal(address(this), governanceParams.minDepositRequirement);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        // Create a proposal
        uint256 proposalId = governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false
        );

        // Attempt to deposit into the proposal with too small of a value
        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientDeposit.selector, 0));
        governance.depositIntoProposal(proposalId, 0);

        // Ensure still in Deposit period
        assertEq(uint8(governance.state(proposalId)), uint8(IGovernor.ProposalState.Deposit));
    }

    function testDepositIntoProposalInsufficientBalance() public {
        // Setup test with enough tokens to make a deposit
        token.mintExternal(address(this), governanceParams.minDepositRequirement);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        // Create a proposal
        uint256 proposalId = governance.propose(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false
        );
        // Our 'shares' are now 0 after the deposit

        // Attempt to make a deposit without the necessary balance to cover the deposit
        vm.expectRevert(abi.encodeWithSelector(Governor.InsufficientBalance.selector, 0));
        governance.depositIntoProposal(proposalId, governanceParams.minDepositRequirement);
    }

    function testDepositIntoProposalInvalidProposal() public {
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, 0));
        governance.depositIntoProposal(0, 1);
    }

    function testDepositIntoProposalInvalidState() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

        // Create a fully funded proposal
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            deposit
        );

        // Attempt to deposit again when we've gone beyond the Deposit stage
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.Voting)));
        governance.depositIntoProposal(proposalId, 1);
    }

    function testClaimDeposit() public {
        address us = address(this);
        address them = address(0xDEADBEEF);

        // Setup our test users with some Vault Shares
        token.mintExternal(us, governanceParams.minDepositRequirement);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        token.mintExternal(them, governanceParams.minDepositRequirement);
        vm.prank(them);
        token.approve(address(governance), governanceParams.minDepositRequirement);

        // Move beyond the minDurationHeld so our tokens become elegible for voting
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Create a proposal as user (us)
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            governanceParams.minDepositRequirement
        );

        // Deposit as (them)
        vm.prank(them);
        governance.depositIntoProposal(proposalId, governanceParams.minDepositRequirement);

        // Roll forward a block to the voting stage
        vm.roll(block.number + 1);

        // Mock a Yes vote majority
        governance.setVotes(proposalId, [0, governanceParams.minDepositRequirement * 2, 0, 0]);

        // Move to the end of the voting period
        vm.roll(block.number + governanceParams.internalParams.votingPeriod + 1);

        // Claim our deposit
        vm.expectEmit(true, false, false, true);
        emit DepositClaimed(us, proposalId, governanceParams.minDepositRequirement);
        governance.claimDeposit(proposalId);

        assertEq(governance.getDeposit(proposalId, us), 0);
        assertEq(governance.getDeposit(proposalId, them), governanceParams.minDepositRequirement);
        assertEq(token.balanceOf(address(governance)), governanceParams.minDepositRequirement);
        assertEq(token.balanceOf(us), governanceParams.minDepositRequirement);
        assertEq(token.balanceOf(them), 0);

        // Mock a NoWithVeto vote majority
        governance.setVotes(proposalId, [0, 0, 0, governanceParams.minDepositRequirement]);

        // Attempt to Claim their deposit with a NoWithVeto majority
        //vm.prank(them);
        //vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.RejectedWithVeto)));
        //governance.claimDeposit(proposalId);

        // Change back to a Yes vote majority
        governance.setVotes(proposalId, [0, governanceParams.minDepositRequirement * 2, 0, 0]);

        // Claim their deposit
        vm.prank(them);
        vm.expectEmit(true, false, false, true);
        emit DepositClaimed(them, proposalId, governanceParams.minDepositRequirement);
        governance.claimDeposit(proposalId);

        assertEq(governance.getDeposit(proposalId, us), 0);
        assertEq(governance.getDeposit(proposalId, them), 0);
        assertEq(token.balanceOf(address(governance)), 0);
        assertEq(token.balanceOf(us), governanceParams.minDepositRequirement);
        assertEq(token.balanceOf(them), governanceParams.minDepositRequirement);

        // Attempt to double claim
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidClaimRequest.selector));
        governance.claimDeposit(proposalId);
    }

    function testClaimDepositInvalidProposal() public {
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, 0));
        governance.claimDeposit(0);
    }

    function testClaimDepositInvalidUser() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;

        // Create a proposal with a sufficient deposit
        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

        // Create a fully funded proposal
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [0, deposit, 0, 0]);

        // Move to the end of the voting period
        vm.roll(block.number + governanceParams.internalParams.votingPeriod + 1);

        // Attempt to claim as a different user
        vm.prank(address(0xDEADBEEF));
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidClaimRequest.selector));
        governance.claimDeposit(proposalId);

        // Claim as us
        governance.claimDeposit(proposalId);
    }

    function testRakeDeposit() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;

        // Create a proposal with a sufficient deposit
        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

        uint256 expectedTotalSupply = token.totalSupply();

        // Move beyond the minDurationHeld so our tokens are factored into the quorum count
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Create a fully funded proposal
        uint256 proposalId = governance.proposeWithDeposit(
            mockProposal.targets,
            mockProposal.values,
            mockProposal.calldatas,
            "Hello, World",
            false,
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [0, deposit, 0, 0]);

        // Move to the end of the voting period
        vm.roll(block.number + governanceParams.internalParams.votingPeriod + 1);

        // Attempt to rake, invalid state
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.Passed)));
        governance.rakeDeposit(proposalId);

        // Setup a No vote majority
        governance.setVotes(proposalId, [deposit, 0, 0, 0]);

        // Attempt to claim our deposit back
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidState.selector, uint8(IGovernor.ProposalState.Rejected)));
        governance.claimDeposit(proposalId);

        // Rake the deposit back into to the share pool
        // as a different user, ensuring anyone can call rake()
        vm.expectEmit(true, false, false, true);
        emit DepositBurned(address(0xDEADBEEF), proposalId, deposit);
        vm.prank(address(0xDEADBEEF));
        governance.rakeDeposit(proposalId);

        // Ensure the shares have been burned
        assertEq(token.balanceOf(address(governance)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), 0);

        // Attempt to rake the proposal deposit again, already been raked
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidRakeRequest.selector));
        governance.rakeDeposit(proposalId);
    }

    function testRakeDepositInvalidProposal() public {
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidProposal.selector, 0));
        governance.rakeDeposit(0);
    }

    function testExecute() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;
        // New params to be set in the contracct
        Governor.ExternalParams memory newParams = Governor.ExternalParams(
            5e18,
            Governor.InternalParams(5, 20, 50, 33, 40, 66, 1, 10e18)
        );

        // Mint enough shares to make a deposit
        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

        // Move beyond the minDurationHeld so our tokens are factored into the quorum count
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Setup the function to call
        bytes memory _calldata = abi.encodeWithSelector(
            Governor.setParams.selector,
            newParams
        );
        ProposalHelper memory _proposal = generateGovernorProp(address(governance), 0, _calldata, "Test Proposal");

        // Create a proposal with a sufficient deposit
        uint256 proposalId = governance.proposeWithDeposit(
            _proposal.targets,
            _proposal.values,
            _proposal.calldatas,
            "Test Proposal",
            false,
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [0, deposit, 0, 0]);

        // Move to the end of the voting period
        vm.roll(block.number + governanceParams.internalParams.votingPeriod + 1);

        // Execute the function, expect a state change to `Executed`
        vm.expectEmit(true, false, false, true);
        emit ProposalStatusChanged(proposalId, uint8(IGovernor.ProposalState.Passed), uint8(IGovernor.ProposalState.Executed));
        governance.execute(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256("Test Proposal"));

        // Ensure the function has executed
        (uint256 newMinDepositRequirement, Governor.InternalParams memory newInternalParams) = governance.params();
        assertEq(newMinDepositRequirement, newParams.minDepositRequirement);
        assertEq(newInternalParams.depositPeriod, newParams.internalParams.depositPeriod);
        assertEq(newInternalParams.depositRequirement, newParams.internalParams.depositRequirement);

        // Ensure status has been set and hooks called
        (,uint8 status,,,) = governance.proposals(proposalId);
        assertEq(status, uint8(IGovernor.ProposalState.Executed));
        assertEq(governance.beforeExecuteCalls(), 1);
        assertEq(governance.afterExecuteCalls(), 1);
    }

    function testExecuteFailure() public {
        uint256 deposit = governanceParams.internalParams.depositRequirement;
        // Setup some invalid parameters
        Governor.ExternalParams memory newParams = Governor.ExternalParams(
            0,
            Governor.InternalParams(0, 20, 50, 33, 40, 66, 1, 10e18)
        );

        token.mintExternal(address(this), deposit);
        token.approve(address(governance), deposit);

        // Move beyond the minDurationHeld so our tokens are factored into the quorum count
        vm.roll(governanceParams.internalParams.minDurationHeld + 1);

        // Setup the function to call with incorrect parameters
        bytes memory _calldata = abi.encodeWithSelector(
            Governor.setParams.selector,
            newParams
        );
        ProposalHelper memory _proposal = generateGovernorProp(address(governance), 0, _calldata, "Test Proposal");

        // Create a proposal with a sufficient deposit
        uint256 proposalId = governance.proposeWithDeposit(
            _proposal.targets,
            _proposal.values,
            _proposal.calldatas,
            "Test Proposal",
            false,
            deposit
        );

        // Setup a Yes vote majority
        governance.setVotes(proposalId, [0, deposit, 0, 0]);

        // Move to the end of the voting period
        vm.roll(block.number + governanceParams.internalParams.votingPeriod + 1);

        // Execute the function, expect a state change to `Executed`
        vm.expectEmit(true, false, false, true);
        emit ProposalStatusChanged(proposalId, uint8(IGovernor.ProposalState.Passed), uint8(IGovernor.ProposalState.Failed));
        governance.execute(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256("Test Proposal"));

        // Ensure the function has not changed the state
        (uint256 newMinDepositRequirement, Governor.InternalParams memory internalParams) = governance.params();
        assertEq(newMinDepositRequirement, governanceParams.minDepositRequirement);
        assertEq(internalParams.depositPeriod, governanceParams.internalParams.depositPeriod);
        assertEq(internalParams.depositRequirement, governanceParams.internalParams.depositRequirement);

        // Ensure status has been set and hooks called
        (,uint8 status,,,) = governance.proposals(proposalId);
        assertEq(status, uint8(IGovernor.ProposalState.Failed));
        assertEq(governance.beforeExecuteCalls(), 1);
        assertEq(governance.afterExecuteCalls(), 1);
    }

    function testOnlyGovernor() public {
        // Attempt as test user
        vm.expectRevert("Permission denied");
        governance.setParams(governanceParams);

        // Attempt as Governor
        vm.prank(address(governance));
        governance.setParams(governanceParams);
    }

    // Forgive me lord, for I have sinned
    // TODO: Refactor this test to dynamically create structs with abi.encode/abi.decode,
    // or create a helper library, because I'm gonna need to do this a ton
    function testParamSanitization() public {
        Governor.ExternalParams memory newParams = governanceParams;
        
        // Invalid constants (must not be Zero)
        // minDepositRequirement, depositPeriod, votingPeriod, minDurationHeld, depositRequirement
        newParams.minDepositRequirement = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.depositPeriod = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.votingPeriod = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.minDurationHeld = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.depositRequirement = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        // Test rangebound parameters
        newParams = governanceParams;
        newParams.internalParams.yesThreshold = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);
        newParams.internalParams.yesThreshold = 101;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.noWithVetoThreshold = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);
        newParams.internalParams.noWithVetoThreshold = 101;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.quorumThreshold = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);
        newParams.internalParams.quorumThreshold = 101;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);

        newParams = governanceParams;
        newParams.internalParams.yesThresholdUrgent = 0;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);
        newParams.internalParams.yesThresholdUrgent = 101;
        vm.expectRevert(abi.encodeWithSelector(Governor.InvalidParams.selector));
        vm.prank(address(governance));
        governance.setParams(newParams);
    }
}