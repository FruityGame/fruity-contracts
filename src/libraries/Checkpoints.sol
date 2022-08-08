// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";

// Modified from OpenZeppelin Contracts v4.5.0 (utils/Checkpoints.sol)
// Changed to use Solmate and reduce project dependencies (Zeppelin is fat)
library Checkpoints {
    struct Checkpoint {
        uint32 _blockNumber;
        uint224 _value;
    }

    struct History {
        Checkpoint[] _checkpoints;
    }

    function latest(History storage history) internal view returns (uint256) {
        uint256 index = history._checkpoints.length;
        if (index == 0) return 0;

        return history._checkpoints[index - 1]._value;
    }

    // Ensures the latest value for the user is not from a yet unmined block (for use in Governance)
    function latestChecked(History storage history) internal view returns (uint256) {
        uint256 index = history._checkpoints.length;
        if (index == 0) return 0;

        require(history._checkpoints[index - 1]._blockNumber < block.number, "Checkpoints: Block not yet mined");
        return history._checkpoints[index - 1]._value;
    }

    function getAtBlock(History storage history, uint256 blockNumber) internal view returns (uint256) {
        require(blockNumber < block.number, "Checkpoints: Block not yet mined");

        uint256 high = history._checkpoints.length;

        // Optimistic check
        if (high != 0 && history._checkpoints[high - 1]._blockNumber <= blockNumber) {
            return history._checkpoints[high - 1]._value;
        }

        uint256 low = 0;
        uint256 mid = 0;

        while (low < high) {
            mid = average(low, high);
            if (history._checkpoints[mid]._blockNumber > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        if (high == 0) return 0;
        return history._checkpoints[high - 1]._value;
    }

    function push(History storage history, uint256 value) internal returns (uint256, uint256) {
        uint256 index = history._checkpoints.length;
        uint256 old = latest(history);

        if (index > 0 && history._checkpoints[index - 1]._blockNumber == block.number) {
            history._checkpoints[index - 1]._value = SafeCastLib.safeCastTo224(value);
        } else {
            history._checkpoints.push(
                Checkpoint({_blockNumber: SafeCastLib.safeCastTo32(block.number), _value: SafeCastLib.safeCastTo224(value)})
            );
        }

        return (old, value);
    }

    /**
     * @dev Pushes a value onto a History, by updating the latest value using binary operation `op`. The new value will
     * be set to `op(latest, delta)`.
     *
     * Returns previous value and new value.
     */
    function push(
        History storage history,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) internal returns (uint256, uint256) {
        return push(history, op(latest(history), delta));
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a & b) + (a ^ b) / 2;
    }
}
