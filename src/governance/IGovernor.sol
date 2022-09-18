// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IGovernor {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        DATA STRUCTURES
    /////////////////////////////////////////////////////////////////////////////////////////*/

    /* 
        The layout of this struct is purposeful:
        Deposit is Index 0, so the default value when a proposal is initiated in storage (as uint8)
    */
    enum ProposalState {
        Deposit,
        Executed,
        Failed,
        Voting,
        Expired,
        Passed,
        Rejected,
        RejectedWithVeto
    }

    enum Vote {
        None, // Reserve slot 0
        No,
        Yes,
        Abstain,
        NoWithVeto
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

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

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                      EXTERNAL METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    function COUNTING_MODE() external pure returns (string memory);

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);

    function state(uint256 proposalId) external view returns (ProposalState);

    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    function proposalQuorum(uint256 proposalId) external view returns (uint256);

    function proposalDeposit(uint256 proposalId) external view returns (uint256);

    function getTallyFor(uint256 proposalId, uint8 vote) external view returns (uint256);

    function getUserVote(uint256 proposalId, address account) external view returns (uint8);

    function quorum(uint256 proposalId) external view returns (bool);

    function getVotes(address account, uint256 blockNumber) external view returns (uint256);

    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        bool urgent
    ) external returns (uint256 proposalId);

    function proposeWithDeposit(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        bool urgent,
        uint256 deposit
    ) external returns (uint256 proposalId);

    function depositIntoProposal(uint256 proposalId, uint256 deposit) external;

    // Allows people to claim their deposit back in the event that the proposal does not pass/execute
    function claimDeposit(uint256 proposalId) external;

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256 proposalId);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 balance);

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external returns (uint256 balance);

    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 balance);

    function castVoteWithReasonBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 balance);
}
