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

    uint256 constant internal NUM_VOTES = 4;

    // Array indices for vote counting/access
    uint8 constant internal NO_VOTE = uint8(VoteType.No) - 1;
    uint8 constant internal YES_VOTE = uint8(VoteType.Yes) - 1;
    uint8 constant internal ABSTAIN_VOTE = uint8(VoteType.Abstain) - 1;
    uint8 constant internal NO_WITH_VETO_VOTE = uint8(VoteType.NoWithVeto) - 1;

    struct Proposal {
        uint248 statusStartBlock; // Block # the status was set at
        uint8 status; // Status (Deposit, Executed, Failed, Voting)
        uint256 depositTotal; // Total deposit
        Params params; // Params on proposal creation
        mapping(address => uint256) deposits;
    }

    struct Ballot {
        uint256[NUM_VOTES] votes;
        mapping(address => uint8) record;
    }

    enum VoteType {
        None, // Reserve slot 0
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
    mapping(uint256 => Ballot) internal ballots;

    /*
        Governance related storage
    */
    uint256 public minProposalDeposit;
    Params public params;

    modifier onlyGovernance() virtual {
        require(msg.sender == address(this), "Permission denied");
        _;
    }

    modifier isValidVote(uint256 vote) {
        require(vote > 0 && vote <= NUM_VOTES, "Invalid Vote");
        _;
    }

    modifier isValidParams(Params memory _params) {
        require(_params.depositPeriod > 0, "Invalid Param: depositPeriod");
        require(_params.votingPeriod > 0, "Invalid Param: votingPeriod");
        require(_params.yesThreshold > 0 && params.yesThreshold <= 100, "Invalid Param: yesThreshold");
        require(_params.noWithVetoThreshold > 0 && params.noWithVetoThreshold <= 100, "Invalid Param: noWithVetoThreshold");
        require(_params.quorumThreshold > 0 && params.quorumThreshold <= 100, "Invalid Param: quorumThreshold");
        require(_params.depositRequirement > 0, "Invalid Param: depositRequirement");
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
        return "quorum=yes,no,abstain,noWithVeto";
    }

    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        uint256 statusStartBlock = proposal.statusStartBlock;
        require(statusStartBlock != 0, "Invalid Proposal");

        // Get current status (Deposit (0) | Executed (1) | Failed (2) | Voting (3))
        uint8 status = proposal.status;

        // If our status is Deposit and we didn't receive a sufficient deposit in time
        if (status == uint8(ProposalState.Deposit) && block.number > statusStartBlock + proposal.params.depositPeriod) {
            return ProposalState.Expired;
        }

        // If our status is Voting and have reached the end of the Voting Period (deadline)
        if (status == uint8(ProposalState.Voting) && block.number > statusStartBlock + proposal.params.votingPeriod) {
            // No quorum means proposal has failed
            if (!quorum(proposalId)) return ProposalState.Failed;

            // ProposalState.Passed | ProposalState.Rejected | ProposalState.RejectedWithVeto
            return _tally(proposalId);
        }

        // ProposalState.Deposit | ProposalState.Voting | ProposalState.Executed | ProposalState.Failed
        return ProposalState(status);
    }

    /*
        Proposal related methods
    */

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return proposals[proposalId].statusStartBlock;
    }

    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.status == uint8(ProposalState.Deposit)) {
            return proposal.statusStartBlock + proposal.params.depositPeriod;
        }

        return proposal.statusStartBlock + proposal.params.votingPeriod;
    }

    function proposalQuorum(uint256 proposalId) public view virtual override returns (uint256) {
        return proposals[proposalId].params.quorumThreshold;
    }

    function quorum(uint256 proposalId) public view virtual override returns (bool) {
        uint256[NUM_VOTES] storage votes = ballots[proposalId].votes;

        uint256 tally = votes[NO_VOTE] + votes[YES_VOTE] + votes[ABSTAIN_VOTE] + votes[NO_WITH_VETO_VOTE];
        uint256 historicalSupply = totalSupplyCheckpoints.getAtBlock(proposalSnapshot(proposalId));

        return
            tally > 0 &&
            historicalSupply > 0 &&
            tally.mulDivUp(100, historicalSupply) > proposalQuorum(proposalId)
        ;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256 proposalId) {
        proposalId = proposeWithDeposit(
            targets,
            values,
            calldatas,
            description,
            minProposalDeposit
        );
    }

    function proposeWithDeposit(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 deposit
    ) public virtual override returns (uint256 proposalId) {
        require(deposit >= minProposalDeposit, "Invalid Deposit");

        // Ensure the received proposal actually contains something
        require(
            targets.length > 0 &&
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Invalid Proposal"
        );

        // Ensure proposal doesn't already exist
        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        Proposal storage proposal = proposals[proposalId];
        require(proposal.statusStartBlock == 0, "Proposal already exists");

        proposal.params = params;

        // Take the deposit from the proposer. If our deposit is sufficient (_deposit returns true), 
        // begin the voting period straight away. If not, set the statusStartBlock to our current block.
        if (_deposit(proposalId, deposit)) {
            _beginVotingPeriod(proposalId);
        } else {
            proposal.statusStartBlock = uint248(block.number);
            // proposal.status is by default set to 0, which is `Deposit` in the `ProposalStatus` Enum
        }

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            uint8(proposal.status),
            uint248(block.number),
            description
        );
    }

    function depositIntoProposal(uint256 proposalId, uint256 deposit) public virtual override {
        require(deposit > 0, "Invalid deposit");
        require(state(proposalId) == ProposalState.Deposit, "Proposal is not in Deposit stage");

        // If the deposit was sufficient for the Proposal depositRequirements, change to Voting state
        if (_deposit(proposalId, deposit)) {
            emit ProposalStatusChanged(proposalId, uint8(ProposalState.Deposit), uint8(ProposalState.Voting));
            _beginVotingPeriod(proposalId);
        }
    }

    // Allows people to claim their deposit back in the event that the proposal does not pass/execute
    function claimDeposit(uint256 proposalId) public virtual override {
        // State checks the validity of the proposalId
        ProposalState _state = state(proposalId);
        require(
            _state == ProposalState.Passed ||
            _state == ProposalState.Rejected ||
            _state == ProposalState.Executed ||
            _state == ProposalState.Failed,
            "Invalid claim request"
        );

        // Ensure we've not already claimed
        Proposal storage proposal = proposals[proposalId];
        uint256 depositAmount = proposal.deposits[msg.sender];
        require(depositAmount != 0, "Invalid claim request");

        // Zero out their deposit and transfer it to them
        delete proposal.deposits[msg.sender];
        _transferFrom(address(this), msg.sender, depositAmount);

        emit DepositClaimed(msg.sender, proposalId, depositAmount);
    }

    function _deposit(uint256 proposalId, uint256 deposit) internal virtual returns (bool) {
        Proposal storage proposal = proposals[proposalId];

        _transferFrom(msg.sender, address(this), deposit);

        uint256 newDepositTotal = (proposal.depositTotal += deposit);
        proposal.deposits[msg.sender] += deposit;

        emit DepositReceived(msg.sender, proposalId, deposit);

        return newDepositTotal >= proposal.params.depositRequirement;
    }

    function _beginVotingPeriod(uint256 proposalId) internal virtual {
        Proposal storage proposal = proposals[proposalId];
        // Take a snapshot of the Total Vault Share supply at the current block
        totalSupplyCheckpoints.push(totalSupply);

        proposal.statusStartBlock = uint248(block.number);
        proposal.status = uint8(ProposalState.Voting);
    }

    /*
        Execution related methods
    */

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        require(state(proposalId) == ProposalState.Passed, "Could not execute proposal");

        Proposal storage proposal = proposals[proposalId];
        proposal.status = uint8(ProposalState.Executed);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        bool success = _execute(proposalId, targets, values, calldatas, descriptionHash);

        if (!success) {
            proposal.status = uint8(ProposalState.Failed);
            emit ProposalStatusChanged(proposalId, uint8(ProposalState.Passed), uint8(ProposalState.Failed));
        } else {
            emit ProposalStatusChanged(proposalId, uint8(ProposalState.Passed), uint8(ProposalState.Executed));
        }

        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32
    ) internal virtual returns (bool) {
        uint256 targetsLength = targets.length;
        uint256 failed = 0;

        for (uint256 i = 0; i < targetsLength; ++i) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) failed |= 1;
        }

        return failed == 0;
    }

    /*
        Voting related methods
    */

    function getBallot(uint256 proposalId) public view virtual returns (uint256[NUM_VOTES] memory) {
        return ballots[proposalId].votes;
    }

    function getTallyFor(uint256 proposalId, uint8 vote) public view virtual
        isValidVote(vote)
    returns (uint256) {
        return ballots[proposalId].votes[vote - 1];
    }

    function getVote(uint256 proposalId, address account) public view virtual returns (uint8) {
        return ballots[proposalId].record[account];
    }

    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return sharesCheckpoints[account].getAtBlock(blockNumber);
    }

    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return ballots[proposalId].record[account] != uint8(VoteType.None);
    }

    function castVote(uint256 proposalId, uint8 vote) public virtual override returns (uint256 balance) {
        balance = _castVote(proposalId, vote);
        emit VoteCast(msg.sender, proposalId, vote, balance, "");
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 vote,
        string calldata reason
    ) public virtual override returns (uint256 balance) {
        balance = _castVote(proposalId, vote);
        emit VoteCast(msg.sender, proposalId, vote, balance, reason);
    }

    function castVoteBySig(
        uint256 proposalId,
        uint8 vote,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256 balance) {}

    function castVoteWithReasonBySig(
        uint256 proposalId,
        uint8 vote,
        string calldata reason,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256 balance) {}

    function _castVote(uint256 proposalId, uint8 vote) internal virtual returns (uint256 weight) {
        require(state(proposalId) == ProposalState.Voting, "Proposal is not in Voting Period");

        weight = getVotes(msg.sender, proposalSnapshot(proposalId));
        _recordVote(proposalId, msg.sender, vote, weight);
    }

    function _recordVote(
        uint256 proposalId,
        address account,
        uint8 vote,
        uint256 weight
    ) internal virtual isValidVote(vote) {
        // `vote` is an index from 1-4 as per the VoteType enum
        Ballot storage ballot = ballots[proposalId];
        uint8 existingVote = ballot.record[account];

        require(vote != existingVote, "Vote already cast");

        // If we're changing our vote
        if (existingVote != uint8(VoteType.None)) {
            ballot.votes[existingVote - 1] -= weight;
            emit VoteChanged(account, proposalId, existingVote, vote);
        }

        ballot.record[account] = vote;
        // Shift down to fit the array indicies (0-3)
        ballot.votes[vote - 1] += weight;
    }

    function _tally(uint256 proposalId) internal view virtual returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        uint256[NUM_VOTES] storage votes = ballots[proposalId].votes;

        uint256 votesForNo = votes[NO_VOTE] + votes[NO_WITH_VETO_VOTE];
        uint256 tallyWithoutAbstain = votesForNo + votes[YES_VOTE];
        uint256 tally = tallyWithoutAbstain + votes[ABSTAIN_VOTE];

        // If noWithVeto makes up <x>% of the vote
        if (votes[NO_WITH_VETO_VOTE].mulDivUp(100, tally) > proposal.params.noWithVetoThreshold) {
            return ProposalState.RejectedWithVeto;
        }

        // If we have enough yes votes
        if (votes[YES_VOTE].mulDivUp(100, tallyWithoutAbstain) > proposal.params.yesThreshold) {
            return ProposalState.Passed;
        }

        return ProposalState.Rejected;
    }

    function _transferFrom(address from, address to, uint256 amount) internal virtual {
        require(balanceOf[from] >= amount, "Insufficient Vault Shares to make deposit");

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
    function afterBurn(address owner, address, uint256) internal virtual override {
        sharesCheckpoints[owner].push(balanceOf[owner]);
    }

    function afterDeposit(address receiver, uint256, uint256) internal virtual override {
        sharesCheckpoints[receiver].push(balanceOf[receiver]);
    }

    /*
        Governance related parameter exposure
    */

    function setParams(Params memory _params) external onlyGovernance() isValidParams(_params) {
        params = _params;
    }

    function getParams() public view virtual returns (Params memory) {
        return params;
    }
}