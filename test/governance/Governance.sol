// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import { IGovernor } from "src/governance/IGovernor.sol";
import { Governance } from "src/governance/Governance.sol";
import { MockGovernance } from "test/mocks/governance/MockGovernance.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

contract CheckpointsTest is Test {
    using FixedPointMathLib for uint256;

    MockGovernance governance;
    MockERC20 token;

    uint256 constant minProposalDeposit = 10e18;
    Governance.Params governanceParams;

    struct ProposalHelper {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
    }

    function setUp() public virtual {
        token = new MockERC20(0);
        governanceParams = Governance.Params(10, 20, 50, 33, 40, minProposalDeposit * 2);
        governance = new MockGovernance(
            minProposalDeposit,
            governanceParams,
            token, "Mock Governance", "MGT"
        );
    }

    function generateGovernanceProp(
        address target,
        uint256 value,
        bytes memory _calldata,
        string memory description
    ) internal view
    returns (ProposalHelper memory) {
        address[] memory targets = new address[](1);
        targets[0] = target;

        uint256[] memory values = new uint256[](1);
        values[0] = value;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = _calldata;

        bytes32 descriptionHash = bytes32(keccak256(abi.encode(description)));

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
        assertEq(governance._quorumReachedExternal(1), false);

        // Create a proposal with ID 0
        governance.setProposal(
            0,
            10, // Deposit Period End/Vote Period Start
            20, // Vote Period End
            uint8(IGovernor.ProposalState.Executed),
            10e18,
            governanceParams
        );
        governance.pushTotalSupplyCheckpoint(10e18);

        // Roll forward to Voting Period Start
        vm.roll(11);

        // No votes
        assertEq(governance._quorumReachedExternal(0), false);

        // 40%, should not be quorum
        governance.setVotes(0, 1e18, 1e18, 1e18, 1e18);
        assertEq(governance._quorumReachedExternal(0), false);

        // 41%, should be quorum
        governance.setVotes(0, 1e18, 1e18, 1e18, 1.1e18);
        assertEq(governance._quorumReachedExternal(0), true);
    }

    function testStateInvalidProposal() public {
        vm.expectRevert("Invalid Proposal");
        governance.state(0);

        governance.setProposal(
            0,
            10,
            20,
            uint8(IGovernor.ProposalState.Executed),
            minProposalDeposit,
            governanceParams
        );

        vm.expectRevert("Invalid Proposal");
        governance.state(1);
    }

    function testStateLifecycle() public {
        uint256 depositRequirement = governanceParams.depositRequirement;

        // Proposal not yet set
        vm.expectRevert("Invalid Proposal");
        governance.state(0);

        // Setup a proposal with amount < required
        governance.setProposal(
            0,
            10, // Deposit Period End/Vote Period Start
            20, // Vote Period End
            uint8(IGovernor.ProposalState.Executed), // Set Erronous State
            depositRequirement - 1,
            governanceParams
        );
        // Setup totalSupply as propose() does
        governance.pushTotalSupplyCheckpoint(10e18);

        assert(governance.state(0) == IGovernor.ProposalState.Deposit);

        // Move forward beyond the Deposit Period end
        vm.roll(11);

        // Insufficient deposit received
        assert(governance.state(0) == IGovernor.ProposalState.Expired);

        // Set the deposit to be sufficient enough
        governance.setProposal(
            0,
            10,
            20,
            uint8(IGovernor.ProposalState.Deposit),
            depositRequirement,
            governanceParams
        );

        // Move forward beyond the Voting Period end
        vm.roll(21);
        assert(governance.state(0) == IGovernor.ProposalState.Expired);

        // Move back to during the Voting Period end
        vm.roll(11);

        // No votes, but in Voting Period
        assert(governance.state(0) == IGovernor.ProposalState.Voting);

        // Set the # of Yes votes to be greater than the Yes threshold (> 50% of tally)
        governance.setVotes(0, 5e18, 3e18, 2e18, 0);
        assert(governance.state(0) == IGovernor.ProposalState.Passed);

        // Set the # of Yes votes to be 50%
        governance.setVotes(0, 5e18, 5e18, 0, 0);
        assert(governance.state(0) == IGovernor.ProposalState.Rejected);

        // Set the # of NoWithVeto votes to be greater than the NoWithVeto threshold, but with with Abstains
        governance.setVotes(0, 2e18, 1.6e18, 5e18, 3.3e18);
        assert(governance.state(0) == IGovernor.ProposalState.Rejected);

        // Set the # of NoWithVeto votes to be greater than the NoWithVeto threshold
        governance.setVotes(0, 2e18, 1e18, 2e18, 3.3e18);
        assert(governance.state(0) == IGovernor.ProposalState.RejectedWithVeto);

        // Set to Executed
        governance.setProposal(
            0,
            10,
            20,
            uint8(IGovernor.ProposalState.Executed),
            depositRequirement,
            governanceParams
        );

        assert(governance.state(0) == IGovernor.ProposalState.Executed);

        // Set to Failed (Execution Failed)
        governance.setProposal(
            0,
            10,
            20,
            uint8(IGovernor.ProposalState.Failed),
            depositRequirement,
            governanceParams
        );

        assert(governance.state(0) == IGovernor.ProposalState.Failed);
    }
}