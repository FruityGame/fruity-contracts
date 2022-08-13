// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Governance } from "src/governance/Governance.sol";
import { Checkpoints } from "src/libraries/Checkpoints.sol";
import { AbstractERC4626 } from "src/mixins/AbstractERC4626.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";
import { MockERC20VaultPaymentProcessor } from "test/mocks/payment/MockERC20VaultPaymentProcessor.sol";

contract MockGovernance is Governance, MockERC20VaultPaymentProcessor {
    using Checkpoints for Checkpoints.History;

    uint256 public beforeExecuteCalls;
    uint256 public afterExecuteCalls;

    constructor(
        Governance.ExternalParams memory governanceParams,
        ERC20VaultPaymentProcessor.VaultParams memory vaultParams
    )
        Governance(governanceParams)
        MockERC20VaultPaymentProcessor(vaultParams)
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
        Governance.InternalParams memory params
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

    function pushTotalSupplyCheckpoint(uint256 _totalSupply) external {
        totalSupplyCheckpoints.push(_totalSupply);
    }

    function getTotalSupplyCheckpoint(uint256 blockNumber) external view returns (uint256) {
        return totalSupplyCheckpoints.getAtBlock(blockNumber);
    }

    function getDeposit(uint256 proposalId, address user) external view returns (uint256) {
        return proposals[proposalId].deposits[user];
    }

    /*
        ERC20 Hooks Overrides
    */

    function _afterMint(address to, uint256 newBalance, uint256 newTotalSupply) internal virtual override(Governance, MockERC20VaultPaymentProcessor) {
        Governance._afterMint(to, newBalance, newTotalSupply);
    }

    function _afterBurn(address from, uint256 newBalance, uint256 newTotalSupply) internal virtual override(Governance, MockERC20VaultPaymentProcessor) {
        Governance._afterMint(from, newBalance, newTotalSupply);
    }

    function _afterTransfer(address from, address to, uint256 fromNewBalance, uint256 toNewBalance) internal virtual override(Governance, MockERC20VaultPaymentProcessor) {
        Governance._afterTransfer(from, to, fromNewBalance, toNewBalance);
    }

    /*
        ERC4626 Hook Overrides
    */

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual override(ERC20VaultPaymentProcessor, AbstractERC4626) {
        ERC20VaultPaymentProcessor.beforeWithdraw(assets, shares);
    }
}