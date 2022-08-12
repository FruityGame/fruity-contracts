// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

// OpenZeppelin Governor interface without name() as Solmate ERC20 already defines name
abstract contract IGovernor {
    /* 
        The layout of this struct is purposeful:
        Deposit is Index 0, so the default value when a proposal is initiated in storage (as uint8)
    */
    enum ProposalState {
        // Deposit, Executed and Failed are all purposefully aligned next to one another
        // so that we can simply evaluate whether proposal.state < 3 to check whether we're one
        // of the three
        Deposit,
        Executed,
        Failed,
        //
        Voting,
        Expired,
        Passed,
        Rejected,
        RejectedWithVeto
    }

    /*
        Events
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

    /*
        Auxillary methods
    */
    function version() public view virtual returns (string memory);

    function COUNTING_MODE() public pure virtual returns (string memory);

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual returns (uint256);

    function state(uint256 proposalId) public view virtual returns (ProposalState);

    function proposalSnapshot(uint256 proposalId) public view virtual returns (uint256);

    function proposalDeadline(uint256 proposalId) public view virtual returns (uint256);

    function proposalQuorum(uint256 proposalId) public view virtual returns (uint256);

    //function votingDelay() public view virtual returns (uint256);

    //function votingPeriod() public view virtual returns (uint256);

    function quorum(uint256 proposalId) public view virtual returns (bool);

    function getVotes(address account, uint256 blockNumber) public view virtual returns (uint256);

    function hasVoted(uint256 proposalId, address account) public view virtual returns (bool);

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual returns (uint256 proposalId);

    function proposeWithDeposit(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 deposit
    ) public virtual returns (uint256 proposalId);

    function depositIntoProposal(uint256 proposalId, uint256 deposit) public virtual;

    // Gets how much of a deposit contribution address `user` has made to Proposal with ID `proposalId`
    //function getDeposit(uint256 proposalId, address user) public virtual returns (uint256);

    // Allows people to claim their deposit back in the event that the proposal does not pass/execute
    function claimDeposit(uint256 proposalId) public virtual;

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual returns (uint256 proposalId);

    function castVote(uint256 proposalId, uint8 support) public virtual returns (uint256 balance);

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual returns (uint256 balance);

    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256 balance);

    function castVoteWithReasonBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256 balance);
}
