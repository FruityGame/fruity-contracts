// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Governance } from "src/governance/Governance.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";
import { MockERC20VaultPaymentProcessor } from "test/mocks/payment/MockERC20VaultPaymentProcessor.sol";

contract MockGovernance is Governance, MockERC20VaultPaymentProcessor {
    using Checkpoints for Checkpoints.History;

    uint256 public beforeExecuteCalls;
    uint256 public afterExecuteCalls;

    constructor(
        uint256 minProposalDeposit, Governance.Params memory governanceParams,
        ERC20 asset, string memory name, string memory symbol
    )
        Governance(minProposalDeposit, governanceParams)
        MockERC20VaultPaymentProcessor(asset, name, symbol)
    {}

    function afterBurn(address owner, address receiver, uint256 shares) internal override(Governance, MockERC20VaultPaymentProcessor) {
        Governance.afterBurn(owner, receiver, shares);
    }

    function afterDeposit(address owner, uint256 assets, uint256 shares) internal override(Governance, MockERC20VaultPaymentProcessor) {
        Governance.afterDeposit(owner, assets, shares);
    }

    function _beforeExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override {
        beforeExecuteCalls++;
    }

    function _afterExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
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
        uint256 depositTotal,
        Governance.Params memory params
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        proposal.statusStartBlock = uint248(statusStartBlock);
        proposal.status = status;
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

    function pushTotalSupplyCheckpoint(uint256 _totalSupply) external {
        totalSupplyCheckpoints.push(_totalSupply);
    }

    function getTotalSupplyCheckpoint(uint256 blockNumber) external returns (uint256) {
        return totalSupplyCheckpoints.getAtBlock(blockNumber);
    }

    function getDeposit(uint256 proposalId, address user) external returns (uint256) {
        return proposals[proposalId].deposits[user];
    }
}