// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { IGovernor } from "src/governance/IGovernor.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";
import { AbstractERC4626 } from "src/mixins/AbstractERC4626.sol";

// TODO: Require in constructor that the ERC20 (totalSupply * decimals) <= type(uint128).max
abstract contract Governance is IGovernor, AbstractERC4626 {
    using Checkpoints for Checkpoints.History;
    using FixedPointMathLib for uint256;

    struct Proposal {
        uint8 status;
        uint120 voteStart; // # of blocks
        uint128 voteEnd; // # of blocks
        uint256 deposit;
    }

    struct Ballot {
        uint256 no;
        uint256 yes;
        uint256 abstain;
        uint256 noWithVeto;
        mapping(address => bool) hasVoted;
    }

    enum VoteType {
        No,
        Yes,
        Abstain,
        NoWithVeto
    }

    struct GovernanceParams {
        uint64 votingDelay; // # of blocks
        uint64 votingPeriod; // # of blocks
        uint128 quorumThreshold; // 1e18-100e18
        uint256 depositRequirement;
    }

    event DepositReceived(address indexed user, uint256 amount);

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");
    bytes32 internal constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    
    /*
        Votes related storage
    */
    Checkpoints.History private _totalCheckpoints;
    Checkpoints.History private _totalSupplyCheckpoints;
    Checkpoints.History private _quorumCheckpoints;
    mapping(address => Checkpoints.History) private _sharesCheckpoints;

    /*
        Proposal related storage
    */
    mapping(uint256 => Proposal) public _proposals;
    mapping(uint256 => Ballot) public _ballots;

    /*
        Governance related storage
    */
    GovernanceParams public params;

    modifier onlyGovernance() virtual {
        require(msg.sender == address(this), "Permission denied");
        _;
    }

    function version() public view virtual override returns (string memory) {
        return "1";
    }

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "quorum=yes,no,noWithVeto";
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        // Safer to do it this way to prevent the contract locking up
        // trying to convert an invalid uint8 to an ProposalState enumeration
        uint8 status = _proposals[proposalId].status;
        if (status == uint8(ProposalState.Executed) || status == uint8(ProposalState.Cancelled)) {
            return ProposalState(status);
        }

        uint256 snapshot = proposalSnapshot(proposalId);
        if (snapshot == 0) revert("Unknown Proposal ID");
        if (snapshot >= block.number) return ProposalState.Pending;

        uint256 deadline = proposalDeadline(proposalId);
        if (deadline >= block.number) return ProposalState.Active;

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        }

        return ProposalState.Failed;
    }

    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart;
    }

    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteEnd;
    }

    function votingDelay() public view virtual override returns (uint256) {
        return params.votingDelay;
    }

    function votingPeriod() public view virtual override returns (uint256) {
        return params.votingPeriod;
    }

    function quorum(uint256 blockNumber) public view virtual override returns (uint256) {
        // TODO: Enforce via gov params that quorumThreshold > 0 && quorumThreshold <= 100e18
        return _totalSupplyCheckpoints.getAtBlock(blockNumber).mulDivUp(getQuorumAtBlock(blockNumber), 100e18);
    }

    function _quorumReached(uint256 proposalId) internal view virtual returns (bool) {
        Ballot storage votes = _ballots[proposalId];

        return votes.yes + votes.abstain >= quorum(proposalSnapshot(proposalId));
    }

    function getQuorumAtBlock(uint256 blockNumber) internal view virtual returns (uint256) {
        // If history is empty, fallback to old storage
        uint256 length = _quorumCheckpoints._checkpoints.length;
        if (length == 0) return params.quorumThreshold;

        // Optimistic search, check the latest checkpoint
        Checkpoints.Checkpoint memory latest = _quorumCheckpoints._checkpoints[length - 1];
        if (latest._blockNumber <= blockNumber) return latest._value;

        // Otherwize, do the binary search
        return _quorumCheckpoints.getAtBlock(blockNumber);
    }

    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return _sharesCheckpoints[account].getAtBlock(blockNumber);
    }

    function getVotesWithParams(
        address account,
        uint256 blockNumber,
        bytes memory
    ) public view virtual override returns (uint256) {
        return getVotes(account, blockNumber);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256 proposalId) {
        // Ensure the received proposal actually contains something
        require(
            targets.length > 0 &&
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Invalid proposal length"
        );

        // Get deposit requirement (saves multiple SLOADs)
        uint256 deposit = params.depositRequirement;
        require(balanceOf[msg.sender] >= deposit, "Not enough Vault Shares to create proposal");

        // Take the proposal deposit from the user
        balanceOf[msg.sender] -= deposit;
        balanceOf[address(this)] += deposit;

        // Create the proposal if it doesn't already exist
        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        Proposal storage proposal = _proposals[proposalId];
        require(proposal.voteStart == 0, "Proposal already exists");

        _totalSupplyCheckpoints.push(totalSupply);

        uint256 start = block.number + params.votingDelay;
        uint256 end = start + params.votingPeriod;

        // Default ProposalState is 0, aka Pending
        proposal.voteStart = uint120(start);
        proposal.voteEnd = uint128(end);

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            start,
            end,
            description
        );
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        ProposalState status = state(proposalId);

        // if votes.noWithVeto > 33%
        // slash
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued,
            "Could not execute proposal"
        );
        _proposals[proposalId].status = uint8(ProposalState.Executed);

        emit ProposalExecuted(proposalId);

        // Refund Deposit
        // TODO: Logic for retrieving deposit in case a proposal Fails
        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _execute(
        uint256,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32
    ) internal virtual {
        uint256 targetsLength = targets.length;
        for (uint256 i = 0; i < targetsLength; ++i) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "Governor: Execute failed");
        }
    }

    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256 balance) {
        balance = _castVote(proposalId, support);
        emit VoteCast(msg.sender, proposalId, support, balance, "");
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual override returns (uint256 balance) {
        balance = _castVote(proposalId, support);
        emit VoteCast(msg.sender, proposalId, support, balance, reason);
    }

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory
    ) public virtual override returns (uint256 balance) {
        balance = castVoteWithReason(proposalId, support, reason);
    }

    /*function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256 balance);

    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256 balance);*/

    function _castVote(uint256 proposalId, uint8 support) internal virtual returns (uint256 weight) {
        Proposal storage proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Proposal is not yet active");

        weight = getVotes(msg.sender, proposal.voteStart);
        _recordVote(proposalId, msg.sender, support, weight);
    }

    function _recordVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal virtual {
        Ballot storage votes = _ballots[proposalId];
        require(!votes.hasVoted[account], "Account has already voted");

        votes.hasVoted[account] = true;

        if (support == uint8(VoteType.Yes)) {
            votes.yes += weight;
            return;
        }

        if (support == uint8(VoteType.No)) {
            votes.no += weight;
            return;
        }

        if (support == uint8(VoteType.Abstain)) {
            votes.abstain += weight;
            return;
        }

        if (support == uint8(VoteType.NoWithVeto)) {
            votes.noWithVeto += weight;
            return;
        }

        revert("Invalid vote provided");
    }

    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool) {
        Ballot storage votes = _ballots[proposalId];

        return votes.yes > votes.no + votes.noWithVeto;
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Cancelled &&
            status != ProposalState.Expired &&
            status != ProposalState.Executed,
            "Cannot cancel inactive Proposal"
        );

        _proposals[proposalId].status = uint8(ProposalState.Cancelled);

        emit ProposalCanceled(proposalId);
    }

    /*
        Hooks
    */
    function _beforeExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual {}

    function _afterExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual {
        
    }

    /*
        ERC4626 Hooks
    */
    function afterBurn(address owner, address receiver, uint256 shares) internal virtual override {
        _sharesCheckpoints[owner].push(balanceOf[owner]);
        _sharesCheckpoints[receiver].push(balanceOf[receiver] + shares);
    }

    function afterDeposit(address receiver, uint256 assets, uint256 shares) internal virtual override {
        _sharesCheckpoints[receiver].push(balanceOf[receiver]);
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }
}