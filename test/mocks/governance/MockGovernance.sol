// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Governance } from "src/governance/Governance.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";
import { MockERC20VaultPaymentProcessor } from "test/mocks/payment/MockERC20VaultPaymentProcessor.sol";

contract MockGovernance is Governance, MockERC20VaultPaymentProcessor {
    using Checkpoints for Checkpoints.History;

    constructor(
        uint256 minProposalDeposit, Governance.Params memory governanceParams,
        ERC20 asset, string memory name, string memory symbol
    )
        Governance(minProposalDeposit, governanceParams)
        MockERC20VaultPaymentProcessor(asset, name, symbol)
    {}

    function afterBurn(address owner, address receiver, uint256 shares) internal override(Governance, MockERC20VaultPaymentProcessor) {
        super.afterBurn(owner, receiver, shares);
    }

    function afterDeposit(address owner, uint256 assets, uint256 shares) internal override(Governance, MockERC20VaultPaymentProcessor) {
        super.afterDeposit(owner, assets, shares);
    }

    /*
        Mock methods
    */
    function setProposal(
        uint256 proposalId,
        uint256 voteStart,
        uint256 voteEnd,
        uint8 executionStatus,
        uint256 depositTotal,
        Governance.Params memory params
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        proposal.voteStart = uint128(voteStart);
        proposal.voteEnd = uint120(voteEnd);
        proposal.executionStatus = executionStatus;
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
        uint256 yes,
        uint256 no,
        uint256 abstain,
        uint256 noWithVeto
    ) external {
        Ballot storage ballot = ballots[proposalId];
        
        ballot.yes = yes;
        ballot.no = no;
        ballot.abstain = abstain;
        ballot.noWithVeto = noWithVeto;
    }

    function setHasVoted(
        uint256 proposalId,
        address who,
        bool status
    ) external {
        ballots[proposalId].hasVoted[who] = status;
    }

    function _quorumReachedExternal(uint256 proposalId) external returns (bool) {
        return _quorumReached(proposalId);
    }

    function pushTotalSupplyCheckpoint(uint256 _totalSupply) external {
        totalSupplyCheckpoints.push(_totalSupply);
    }

    function getTotalSupplyCheckpoint(uint256 blockNumber) external returns (uint256) {
        return totalSupplyCheckpoints.getAtBlock(blockNumber);
    }
}