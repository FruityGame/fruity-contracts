// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { Counters } from "openzeppelin-contracts/contracts/utils/Counters.sol";
import { Checkpoints } from "openzeppelin-contracts/contracts/utils/Checkpoints.sol";
import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

abstract contract Votes is IVotes {
    using Checkpoints for Checkpoints.History;
    using Counters for Counters.Counter;

    bytes32 internal constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address => address) private _delegation;
    mapping(address => Checkpoints.History) private _delegateCheckpoints;
    Checkpoints.History private _totalCheckpoints;

    mapping(address => Counters.Counter) private _nonces;

    function getVotes(address account) public view virtual override returns (uint256) {
        return _delegateCheckpoints[account].latest();
    }

    function getPastVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return _delegateCheckpoints[account].getAtBlock(blockNumber);
    }
    function getPastTotalSupply(uint256 blockNumber) public view virtual override returns (uint256) {
        require(blockNumber < block.number, "Votes: block not yet mined");
        return _totalCheckpoints.getAtBlock(blockNumber);
    }

    function delegates(address account) public view virtual override returns (address) {
        return _delegation[account];
    }

    function delegate(address delegatee) public virtual override {
        address oldDelegate = delegates(msg.sender);
        _delegation[msg.sender] = delegatee;

        emit DelegateChanged(msg.sender, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(msg.sender));
    }

    function _moveDelegateVotes(
        address from,
        address to,
        uint256 amount
    ) private {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                (uint256 oldValue, uint256 newValue) = _delegateCheckpoints[from].push(_subtract, amount);
                emit DelegateVotesChanged(from, oldValue, newValue);
            }
            if (to != address(0)) {
                (uint256 oldValue, uint256 newValue) = _delegateCheckpoints[to].push(_add, amount);
                emit DelegateVotesChanged(to, oldValue, newValue);
            }
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }

    function _getVotingUnits(address) internal view virtual returns (uint256);
}