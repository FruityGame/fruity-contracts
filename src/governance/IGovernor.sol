// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

// OpenZeppelin Governor interface without name() as Solmate ERC20 already defines name
abstract contract IGovernor {
    // The layout of this struct is purposeful:
    // Deposit is Index 0, so the default value when a proposal is initiated in storage (as uint8)
    // (note) is named differently
    enum ProposalState {
        Deposit,
        Voting,
        Expired,
        Passed,
        Rejected,
        RejectedWithVeto,
        Executed,
        Failed
    }

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event ProposalCanceled(uint256 proposalId);
    event ProposalExecuted(uint256 proposalId);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
    event VoteCastWithParams(
        address indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 weight,
        string reason,
        bytes params
    );

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

    function votingDelay() public view virtual returns (uint256);

    function votingPeriod() public view virtual returns (uint256);

    function quorum(uint256 blockNumber) public view virtual returns (uint256);

    function getVotes(address account, uint256 blockNumber) public view virtual returns (uint256);

    function getVotesWithParams(
        address account,
        uint256 blockNumber,
        bytes memory params
    ) public view virtual returns (uint256);

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

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual returns (uint256 balance);

    function castVoteBySig(
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
    ) public virtual returns (uint256 balance);
}
