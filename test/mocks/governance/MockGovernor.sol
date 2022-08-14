// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { Governor } from "src/governance/Governor.sol";
import { ERC20Snapshot } from "src/tokens/ERC20Snapshot.sol";

contract MockGovernor is Governor {
    uint256 public beforeExecuteCalls;
    uint256 public afterExecuteCalls;

    constructor(
        ERC20Snapshot sharesContract,
        Governor.ExternalParams memory governanceParams
    )
        Governor(sharesContract, governanceParams)
    {}

    function _beforeExecute(
        uint256,
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        bytes32
    ) internal virtual override {
        beforeExecuteCalls++;
    }

    function _afterExecute(
        uint256,
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        bytes32
    ) internal virtual override {
        afterExecuteCalls++;
    }

    /*
        Mock methods
    */
    function setProposal(
        uint256 proposalId,
        uint256 statusStartBlock,
        uint8 status,
        bool urgent,
        uint256 depositTotal,
        Governor.InternalParams memory params
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        proposal.statusStartBlock = uint240(statusStartBlock);
        proposal.status = status;
        proposal.urgent = urgent;
        proposal.depositTotal = depositTotal;
        proposal.params = params;
    }

    function setProposalDeposit(
        uint256 proposalId,
        address who,
        uint256 deposit
    ) external {
        Proposal storage proposal = proposals[proposalId];

        proposal.deposits[who] = deposit;
    }

    function setVotes(
        uint256 proposalId,
        uint256[4] memory votes
    ) external {
        Ballot storage ballot = ballots[proposalId];
        ballot.votes = votes;
    }

    function setVotingRecord(
        uint256 proposalId,
        address who,
        uint8 status
    ) external {
        ballots[proposalId].record[who] = status;
    }

    function getDeposit(uint256 proposalId, address user) external view returns (uint256) {
        return proposals[proposalId].deposits[user];
    }
}