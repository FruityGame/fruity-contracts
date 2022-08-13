// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { Math } from "src/libraries/Math.sol";
import { IGovernor } from "src/governance/IGovernor.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";
import { AbstractERC4626 } from "src/mixins/AbstractERC4626.sol";

abstract contract Governance is IGovernor, AbstractERC4626 {
    using Checkpoints for Checkpoints.History;
    using FixedPointMathLib for uint256;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    uint256 constant internal NUM_VOTE_OPTIONS = 4;

    // Array indices for vote counting/access
    uint8 constant internal NO_VOTE = uint8(Vote.No) - 1;
    uint8 constant internal YES_VOTE = uint8(Vote.Yes) - 1;
    uint8 constant internal ABSTAIN_VOTE = uint8(Vote.Abstain) - 1;
    uint8 constant internal NO_WITH_VETO_VOTE = uint8(Vote.NoWithVeto) - 1;

    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(uint256 proposalId,uint8 vote)");
    bytes32 public constant VOTE_WITH_REASON_TYPEHASH =
        keccak256("VoteWithReason(uint256 proposalId,uint8 vote,string reason)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        DATA STRUCTURES
    /////////////////////////////////////////////////////////////////////////////////////////*/

    struct Proposal {
        uint240 statusStartBlock; // Block # the status was set at
        uint8 status; // Status (Deposit, Executed, Failed, Voting)
        bool urgent;
        uint256 depositTotal; // Total deposit
        InternalParams params; // Params on proposal creation
        mapping(address => uint256) deposits;
    }

    struct Ballot {
        uint256[NUM_VOTE_OPTIONS] votes;
        mapping(address => uint8) record;
    }

    enum Vote {
        None, // Reserve slot 0
        No,
        Yes,
        Abstain,
        NoWithVeto
    }

    // Any params that don't need to be snapshotted per proposal can go in here
    struct ExternalParams {
        uint256 minDepositRequirement;
        InternalParams internalParams;
    }

    // These params will be encapsulated inside each proposal on Snapshot
    struct InternalParams {
        uint32 depositPeriod; // # of blocks
        uint32 votingPeriod; // # of blocks
        uint32 yesThreshold; // 1-100
        uint32 noWithVetoThreshold; // 1-100
        uint32 quorumThreshold; // 1-100
        uint32 yesThresholdUrgent; // 1-100
        uint64 minDurationHeld; // # of blocks
        uint256 depositRequirement;
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    event DepositReceived(address indexed depositor, uint256 indexed proposalId, uint256 amount);
    event DepositClaimed(address indexed depositor, uint256 indexed proposalId, uint256 amount);
    event DepositBurned(address indexed burner, uint256 indexed proposalId, uint256 amount);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    mapping(address => Checkpoints.History) internal sharesCheckpoints;
    Checkpoints.History internal totalSupplyCheckpoints;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Ballot) internal ballots;

    ExternalParams public params;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            MODIFIERS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() virtual {
        require(msg.sender == address(this), "Permission denied");
        _;
    }

    modifier isValidVote(uint256 vote) virtual {
        require(vote > 0 && vote <= NUM_VOTE_OPTIONS, "Invalid Vote");
        _;
    }

    modifier sanitizeParams(ExternalParams memory _params) virtual {
        InternalParams memory internalParams = _params.internalParams;

        require(_params.minDepositRequirement > 0, "Invalid Param: minDepositRequirement");
        require(internalParams.depositPeriod > 0, "Invalid Param: depositPeriod");
        require(internalParams.votingPeriod > 0, "Invalid Param: votingPeriod");
        require(internalParams.yesThreshold > 0 && internalParams.yesThreshold <= 100, "Invalid Param: yesThreshold");
        require(internalParams.noWithVetoThreshold > 0 && internalParams.noWithVetoThreshold <= 100, "Invalid Param: noWithVetoThreshold");
        require(internalParams.quorumThreshold > 0 && internalParams.quorumThreshold <= 100, "Invalid Param: quorumThreshold");
        require(internalParams.yesThresholdUrgent > 0 && internalParams.yesThresholdUrgent <= 100, "Invalid Param: yesThresholdUrgent");
        require(internalParams.minDurationHeld > 0, "Invalid Param: minDurationHeld");
        require(internalParams.depositRequirement > 0, "Invalid Param: depositRequirement");
        _;
    }

    constructor(ExternalParams memory _params) sanitizeParams(_params) {
        params = _params;
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

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

        // If it's an urgent proposal, check to see if a % of the totalSupply at the 
        // snapshot have voted yes. If so, mark the proposal as passed, ending voting early
        if (proposal.urgent && _tallyUrgent(proposalId)) {
            return ProposalState.Passed;
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

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function quorum(uint256 proposalId) public view virtual override returns (bool) {
        uint256[NUM_VOTE_OPTIONS] storage votes = ballots[proposalId].votes;

        // Tally total # of votes received
        uint256 tally = votes[NO_VOTE] + votes[YES_VOTE] + votes[ABSTAIN_VOTE] + votes[NO_WITH_VETO_VOTE];
        uint256 snapshotBlock = proposalSnapshot(proposalId);

        uint256 historicalSupply = totalSupplyCheckpoints.getAtBlock(snapshotBlock);
        // Prevent DivideByZero and save performing the calculation below if it's unecessary
        if (tally == 0 || historicalSupply == 0) return false;

        return tally.mulDivUp(100, historicalSupply) > proposalQuorum(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        bool urgent
    ) public virtual override returns (uint256 proposalId) {
        proposalId = proposeWithDeposit(
            targets,
            values,
            calldatas,
            description,
            urgent,
            params.minDepositRequirement
        );
    }

    function proposeWithDeposit(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        bool urgent,
        uint256 deposit
    ) public virtual override returns (uint256 proposalId) {
        require(deposit >= params.minDepositRequirement, "Invalid Deposit");

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

        // proposal.status is by default set to 0, which is `Deposit` in the `ProposalStatus` Enum
        proposal.statusStartBlock = uint240(block.number);
        proposal.params = params.internalParams;

        // Only set the storage var if the proposal is marked as urgent, saves gas
        if (urgent) proposal.urgent = true;

        // Take the deposit from the proposer. If our deposit is sufficient
        // (_deposit returns true), begin the voting period straight away from this block
        if (_deposit(proposalId, deposit)) {
            proposal.status = uint8(ProposalState.Voting);
        }

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            uint8(proposal.status),
            uint240(block.number),
            urgent,
            description
        );
    }

    function depositIntoProposal(uint256 proposalId, uint256 deposit) public virtual override {
        require(deposit > 0, "Invalid deposit");
        require(state(proposalId) == ProposalState.Deposit, "Proposal is not in Deposit stage");

        // If the deposit was sufficient for the Proposal depositRequirements, change to Voting state
        if (_deposit(proposalId, deposit)) {
            Proposal storage proposal = proposals[proposalId];

            // Update the status to 'Voting' and refresh the statusStartBlock
            proposal.statusStartBlock = uint240(block.number);
            proposal.status = uint8(ProposalState.Voting);

            emit ProposalStatusChanged(proposalId, uint8(ProposalState.Deposit), uint8(ProposalState.Voting));
        }
    }

    // Allows people to claim their deposit back in the event that the proposal does not pass/execute
    function claimDeposit(uint256 proposalId) public virtual override {
        // State checks the validity of the proposalId
        ProposalState _state = state(proposalId);
        require(
            _state == ProposalState.Passed ||
            _state == ProposalState.Failed ||
            _state == ProposalState.Executed ||
            _state == ProposalState.Expired,
            "Invalid claim request"
        );

        // Ensure we've not already claimed
        Proposal storage proposal = proposals[proposalId];
        uint256 depositAmount = proposal.deposits[msg.sender];
        require(depositAmount != 0, "Invalid claim request");

        // Zero out their deposit
        delete proposal.deposits[msg.sender];

        // Send the tokens back to the sender (calls hooks)
        _sendDeposit(msg.sender, depositAmount);

        emit DepositClaimed(msg.sender, proposalId, depositAmount);
    }

    // The reason this function exists, vs burning and minting the user's deposit, is because upon minting/burning,
    // the totalSupply changes, changing the balance of the shares. This means if a user made a significant deposit with
    // their proposal, others would be able to claim their shares for a marginally larger portion of the pot.
    function rakeDeposit(uint256 proposalId) public virtual {
        ProposalState _state = state(proposalId);
        require(
            _state == ProposalState.Rejected ||
            _state == ProposalState.RejectedWithVeto,
            "Invalid rake request"
        );

        // Ensure we've not already claimed
        Proposal storage proposal = proposals[proposalId];
        uint256 depositAmount = proposal.depositTotal;
        require(depositAmount != 0, "Invalid rake request");

        // Zero out the proposal deposit
        delete proposal.depositTotal;

        // Remove the deposit from the share pool
        _burn(address(this), depositAmount);

        emit DepositBurned(msg.sender, proposalId, depositAmount);
    }

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
    
        // _execute() returns true if execution succeeds
        if (_execute(proposalId, targets, values, calldatas, descriptionHash)) {
            emit ProposalStatusChanged(proposalId, uint8(ProposalState.Passed), uint8(ProposalState.Executed));
        } else {
            proposal.status = uint8(ProposalState.Failed);
            emit ProposalStatusChanged(proposalId, uint8(ProposalState.Passed), uint8(ProposalState.Failed));
        }

        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function castVote(uint256 proposalId, uint8 vote) public virtual override returns (uint256 weight) {
        return _castVote(proposalId, msg.sender, vote, "");
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 vote,
        string calldata reason
    ) public virtual override returns (uint256) {
        return _castVote(proposalId, msg.sender, vote, reason);
    }

    function castVoteBySig(
        uint256 proposalId,
        uint8 vote,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            VOTE_TYPEHASH,
                            proposalId,
                            vote
                        )
                    )
                )
            ), v, r, s
        );

        return _castVote(proposalId, recoveredAddress, vote, "");
    }

    function castVoteWithReasonBySig(
        uint256 proposalId,
        uint8 vote,
        string calldata reason,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            VOTE_WITH_REASON_TYPEHASH,
                            proposalId,
                            vote,
                            reason
                        )
                    )
                )
            ), v, r, s
        );

        return _castVote(proposalId, recoveredAddress, vote, reason);
    }

    function proposalBallot(uint256 proposalId) public view virtual returns (uint256[NUM_VOTE_OPTIONS] memory) {
        return ballots[proposalId].votes;
    }

    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        Proposal storage proposal = proposals[proposalId];

        // proposalSnapshot factors into account the minDurationHeld for the snapshot blocks
        return _getBlockWithDelta(proposal.statusStartBlock, proposal.params.minDurationHeld);
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

    function proposalDeposit(uint256 proposalId) public view virtual override returns (uint256) {
        return proposals[proposalId].depositTotal;
    }

    function getTallyFor(uint256 proposalId, uint8 vote) public view virtual override
        isValidVote(vote)
    returns (uint256) {
        return ballots[proposalId].votes[vote - 1];
    }

    function getUserVote(uint256 proposalId, address account) public view virtual override returns (uint8) {
        return ballots[proposalId].record[account];
    }

    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return sharesCheckpoints[account].getAtBlock(blockNumber);
    }

    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return ballots[proposalId].record[account] != uint8(Vote.None);
    }

    function getParams() public view virtual returns (ExternalParams memory) {
        return params;
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        INTERNAL METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function _getBlockWithDelta(uint256 blockNumber, uint256 delta) internal pure returns (uint256) {
        // If the min staking duration hasn't yet passed for this period in time,
        // then nobody can have made a valid deposit of shares. Returning a block #
        // of 0 means that the lookup in Checkpoints will return 0
        if (blockNumber < delta) return 0;
        return blockNumber - delta;
    }

    function _deposit(uint256 proposalId, uint256 deposit) internal virtual returns (bool sufficientDeposit) {
        require(balanceOf[msg.sender] >= deposit, "Insufficient Balance to make Deposit");
        Proposal storage proposal = proposals[proposalId];

        // Take the deposit from the user (calls hooks to update checkpoints)
        transfer(address(this), deposit);

        // Add their deposit to the proposal
        sufficientDeposit = (proposal.depositTotal += deposit) >= proposal.params.depositRequirement;
        proposal.deposits[msg.sender] += deposit;

        emit DepositReceived(msg.sender, proposalId, deposit);
    }

    function _execute(
        uint256,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32
    ) internal virtual returns (bool) {
        uint256 targetsLength = targets.length;

        for (uint256 i = 0; i < targetsLength; ++i) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) return false;
        }

        return true;
    }

    function _castVote(uint256 proposalId, address voter, uint8 vote, string memory reason) internal virtual returns (uint256 weight) {
        require(state(proposalId) == ProposalState.Voting, "Proposal is not in Voting Period");

        weight = getVotes(voter, proposalSnapshot(proposalId));
        _recordVote(proposalId, voter, vote, weight);

        emit VoteCast(msg.sender, proposalId, vote, weight, reason);
    }

    function _recordVote(
        uint256 proposalId,
        address account,
        uint8 vote,
        uint256 weight
    ) internal virtual isValidVote(vote) {
        require(weight > 0, "Insufficient shares to vote with");
        // `vote` is an index from 1-4 as per the Vote enum
        Ballot storage ballot = ballots[proposalId];
        uint8 existingVote = ballot.record[account];

        require(vote != existingVote, "Vote already cast");

        // If we're changing our vote
        if (existingVote != uint8(Vote.None)) {
            ballot.votes[existingVote - 1] -= weight;
            emit VoteChanged(account, proposalId, existingVote, vote);
        }

        ballot.record[account] = vote;
        // Shift down to fit the array indicies (0-3)
        ballot.votes[vote - 1] += weight;
    }

    function _tally(uint256 proposalId) internal view virtual returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        uint256[NUM_VOTE_OPTIONS] storage votes = ballots[proposalId].votes;

        uint256 tallyWithoutAbstain = votes[NO_VOTE] + votes[NO_WITH_VETO_VOTE] + votes[YES_VOTE];
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

    function _tallyUrgent(uint256 proposalId) internal view virtual returns (bool) {
        uint256 yesVotes = ballots[proposalId].votes[YES_VOTE];

        // If snapshot block is 0, then our totalSupply must be Zero
        // (not possible for any totalSupply to be minted at block 0)
        // Also stops divide by zero
        uint256 supplyAtSnapshot = totalSupplyCheckpoints.getAtBlock(proposalSnapshot(proposalId));
        if (supplyAtSnapshot == 0) return false;

        // Calculates using the totalSupply at the snapshot vs only a tally of those who've voted
        // This means > yesThresholdUrgent% of the totalSupply at snapshotBlock must have voted `yes`
        return yesVotes.mulDivUp(100, supplyAtSnapshot) > proposals[proposalId].params.yesThresholdUrgent;
    }

    function _sendDeposit(
        address to,
        uint256 amount
    ) internal virtual returns (bool) {
        emit Transfer(address(this), to, amount);

        _afterTransfer(address(this), to, balanceOf[address(this)] -= amount, balanceOf[to] += amount);

        return true;
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        INTERNAL HOOKS
    /////////////////////////////////////////////////////////////////////////////////////////*/

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

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            ERC20 HOOKS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function _afterMint(address to, uint256 newBalance, uint256 newTotalSupply) internal virtual override {
        sharesCheckpoints[to].push(newBalance);
        totalSupplyCheckpoints.push(newTotalSupply);
    }

    function _afterBurn(address from, uint256 newBalance, uint256 newTotalSupply) internal virtual override {
        // Only update the shares for user `from` if they're not us (i.e. an internal burn)
        if (from != address(this)) sharesCheckpoints[from].push(newBalance);
        totalSupplyCheckpoints.push(newTotalSupply);
    }

    function _afterTransfer(address from, address to, uint256 fromNewBalance, uint256 toNewBalance) internal virtual override {
        sharesCheckpoints[from].push(fromNewBalance);
        sharesCheckpoints[to].push(toNewBalance);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        GOVERNANCE METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function setParams(ExternalParams memory _params) external onlyGovernance() sanitizeParams(_params) {
        params = _params;
    }
}