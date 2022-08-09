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
        uint128 voteStart; // # of blocks
        uint120 voteEnd; // # of blocks
        uint8 executionStatus;
        uint256 depositTotal; // Total deposit
        Params params; // Params on proposal creation
        mapping(address => uint256) deposits;
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

    struct Params {
        uint32 depositPeriod; // # of blocks
        uint32 votingPeriod; // # of blocks
        uint32 yesThreshold; // 1-100
        uint32 noWithVetoThreshold; // 1-100
        uint128 quorumThreshold; // 1-100
        uint256 depositRequirement;
    }

    event DepositReceived(address indexed depositor, uint256 indexed proposalId, uint256 amount);
    event DepositClaimed(address indexed depositor, uint256 indexed proposalId, uint256 amount);

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    /*
        Votes related storage
    */
    mapping(address => Checkpoints.History) internal sharesCheckpoints;
    Checkpoints.History internal totalSupplyCheckpoints;

    /*
        Proposal related storage
    */
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Ballot) public ballots;

    /*
        Governance related storage
    */
    uint256 public minProposalDeposit;
    Params public params;

    modifier onlyGovernance() virtual {
        require(msg.sender == address(this), "Permission denied");
        _;
    }

    constructor(uint256 _minProposalDeposit, Params memory _params) {
        minProposalDeposit = _minProposalDeposit;
        params = _params;
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
        Proposal storage proposal = proposals[proposalId];
        bool insufficientDeposit = proposal.depositTotal < proposal.params.depositRequirement;

        uint256 startBlock = proposal.voteStart;
        require(startBlock != 0, "Invalid Proposal");
        // If voting not yet started (still in Deposit period) and deposit is insufficient
        if (block.number < startBlock && insufficientDeposit) {
            return ProposalState.Deposit;
        }

        // If Deposit period has ended and we still have an insufficient deposit
        if (insufficientDeposit) return ProposalState.Expired;

        // If Proposal has already been executed
        uint8 executionStatus = proposal.executionStatus;
        if (executionStatus == uint8(ProposalState.Executed) || executionStatus == uint8(ProposalState.Failed)) {
            return ProposalState(executionStatus);
        }

        // Quorum reached will return false if no votes have been cast yet
        if (_quorumReached(proposalId)) return _tally(proposalId);

        // If we have a sufficient deposit, but the proposal has not been executed
        // AND quorum has not been reached before the end of the voting period
        if (block.number > proposal.voteEnd) return ProposalState.Expired;

        return ProposalState.Voting;
    }

    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return proposals[proposalId].voteStart;
    }

    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return proposals[proposalId].voteEnd;
    }

    function votingDelay() public view virtual override returns (uint256) {
        return params.depositPeriod;
    }

    function votingPeriod() public view virtual override returns (uint256) {
        return params.votingPeriod;
    }

    function quorum(uint256 proposalId) public view virtual override returns (uint256) {
        // TODO: Enforce via gov params that quorumThreshold > 0 && quorumThreshold <= 100e18
        return proposals[proposalId].params.quorumThreshold;
    }

    function _quorumReached(uint256 proposalId) internal view virtual returns (bool) {
        Ballot storage votes = ballots[proposalId];
        Proposal storage proposal = proposals[proposalId];

        uint256 tally = votes.yes + votes.no + votes.noWithVeto + votes.abstain;
        uint256 historicalSupply = totalSupplyCheckpoints.getAtBlock(proposal.voteStart);

        return
            tally > 0 &&
            historicalSupply > 0 &&
            tally.mulDivUp(100, historicalSupply) > quorum(proposalId)
        ;
    }

    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return sharesCheckpoints[account].getAtBlock(blockNumber);
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

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        // How do you even format such an abomination of a ternary
        (uint256 start, uint256 end) = proposalSnapshot(proposalId) == 0 ?
            _propose(
                proposalId,
                params.depositRequirement
            )
            :
            _propose(
                proposalId,
                proposals[proposalId].params.depositRequirement
            )
        ;

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

    function proposeWithDeposit(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 deposit
    ) public virtual override returns (uint256 proposalId) {
        // Ensure the received proposal actually contains something
        require(
            targets.length > 0 &&
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Invalid proposal length"
        );

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        (uint256 start, uint256 end) = _propose(proposalId, deposit);

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

    function _propose(
        uint256 proposalId,
        uint256 deposit
    ) internal virtual returns (uint256, uint256) {
        Proposal storage proposal = proposals[proposalId];
        require(deposit >= minProposalDeposit, "Invalid Deposit");
        require(proposal.voteStart == 0, "Proposal already exists");

        // Take the deposit from the proposer
        _transferFrom(msg.sender, address(this), deposit);

        // Fresh proposal, take total supply snapshot
        totalSupplyCheckpoints.push(totalSupply);

        uint256 start = block.number + params.depositPeriod;
        uint256 end = start + params.votingPeriod;

        // Default ProposalState is 0, aka Deposit
        proposal.depositTotal = deposit;
        proposals[proposalId].deposits[msg.sender] = deposit;
        // Block # should never exceed 2^40 so should be okay to use uint40/48
        proposal.voteStart = uint40(start);
        proposal.voteEnd = uint48(end);
        proposal.params = params;

        emit DepositReceived(msg.sender, proposalId, deposit);

        return (start, end);
    }

    function depositIntoProposal(
        uint256 proposalId,
        uint256 deposit
    ) public virtual override {
        // State validates the proposalId is a valid proposal
        require(deposit > 0, "Invalid deposit");
        require(state(proposalId) == ProposalState.Deposit, "Proposal is not in Deposit stage");

        // Take the deposit
        _transferFrom(msg.sender, address(this), deposit);
        proposals[proposalId].depositTotal += deposit;
        proposals[proposalId].deposits[msg.sender] += deposit;

        emit DepositReceived(msg.sender, proposalId, deposit);
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        ProposalState status = state(proposalId);

        // Set before calling contracts to prevent reentrancy
        require(status == ProposalState.Passed, "Could not execute proposal");
        proposals[proposalId].executionStatus = uint8(ProposalState.Executed);

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32
    ) internal virtual {
        uint256 targetsLength = targets.length;
        for (uint256 i = 0; i < targetsLength; ++i) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) {
                proposals[proposalId].executionStatus = uint8(ProposalState.Failed);
                revert("Governance execution failed");
            }
        }
    }

    // Allows people to claim their deposit back in the event that the proposal does not pass/execute
    function claimDeposit(uint256 proposalId) public virtual {
        // State checks the validity of the proposalId
        ProposalState _state = state(proposalId);
        require(
            _state == ProposalState.Passed ||
            _state == ProposalState.Rejected ||
            _state == ProposalState.Executed ||
            _state == ProposalState.Failed,
            "Invalid claim request"
        );

        Proposal storage proposal = proposals[proposalId];
        uint256 depositAmount = proposal.deposits[msg.sender];
        require(depositAmount != 0, "Invalid claim request");

        delete proposal.deposits[msg.sender];
        _transferFrom(address(this), msg.sender, depositAmount);

        emit DepositClaimed(msg.sender, proposalId, depositAmount);
    }

    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return ballots[proposalId].hasVoted[account];
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

    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256 balance) {}

    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory _params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256 balance) {}

    function _castVote(uint256 proposalId, uint8 support) internal virtual returns (uint256 weight) {
        Proposal storage proposal = proposals[proposalId];
        require(state(proposalId) == ProposalState.Voting, "Proposal is not yet active");

        weight = getVotes(msg.sender, proposal.voteStart);
        _recordVote(proposalId, msg.sender, support, weight);
    }

    function _recordVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal virtual {
        Ballot storage votes = ballots[proposalId];
        // The Cool way of doing it
        //require(votes.hasVoted[account] = !votes.hasVoted[account], "Account has already voted");

        // The "safer" (citation needed) and more obvious way
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

    function _tally(uint256 proposalId) internal view virtual returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        Ballot storage votes = ballots[proposalId];

        uint256 tallyWithoutAbstain = votes.yes + votes.no + votes.noWithVeto;
        uint256 tally = tallyWithoutAbstain + votes.abstain;
        uint256 votesForNo = votes.no + votes.noWithVeto;

        // If noWithVeto makes up <x>% of the vote
        if (votes.noWithVeto.mulDivUp(100, tally) > proposal.params.noWithVetoThreshold) {
            return ProposalState.RejectedWithVeto;
        }

        // If we have enough yes votes
        if (votes.yes.mulDivUp(100, tallyWithoutAbstain) > proposal.params.yesThreshold) {
            return ProposalState.Passed;
        }

        return ProposalState.Rejected;
    }

    function _transferFrom(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "Not enough Vault Shares to pay deposit");

        // Take the proposal deposit from the user
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
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
    ) internal virtual {}

    /*
        ERC4626 Hooks
    */
    function afterBurn(address owner, address receiver, uint256 shares) internal virtual override {
        sharesCheckpoints[owner].push(balanceOf[owner]);
        sharesCheckpoints[receiver].push(balanceOf[receiver] + shares);
    }

    function afterDeposit(address receiver, uint256 assets, uint256 shares) internal virtual override {
        sharesCheckpoints[receiver].push(balanceOf[receiver]);
    }
}