// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Math } from "src/libraries/Math.sol";
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

    // Ensures the latest value for the user is not from a yet unmined block (for use in Governor)
    function latestChecked(History storage history) internal view returns (uint256) {
        uint256 index = history._checkpoints.length;
        if (index == 0) return 0;

        require(history._checkpoints[index - 1]._blockNumber < block.number, "Checkpoints: Block not yet mined");
        return history._checkpoints[index - 1]._value;
    }

    function getAtBlock(History storage history, uint256 blockNumber) internal view returns (uint256) {
        return getAtBlockFromIndex(history, blockNumber, 0);
    }

    function getAtBlockFromIndex(History storage history, uint256 blockNumber, uint256 index) internal view returns (uint256) {
        require(blockNumber < block.number, "Checkpoints: Block not yet mined");

        uint256 high = history._checkpoints.length;
        require(index <= high, "Invalid Index");

        // Optimistic check
        if (high != 0 && history._checkpoints[high - 1]._blockNumber <= blockNumber) {
            return history._checkpoints[high - 1]._value;
        }

        uint256 low = index;
        uint256 mid = 0;

        while (low < high) {
            mid = Math.average(low, high);
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

    function push(
        History storage history,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) internal returns (uint256, uint256) {
        return push(history, op(latest(history), delta));
    }

    /* Gets a starting index from the positon of the current array length,
     * using a delta value. The delta value can be thought of as defining a
     * maximum bounds for the space we want to search with the binary search in
     * getAtBlockFromIndex(). I.e:
        history.length == 1024
        indexDelta == 256

        1024 - 256 = startIndex of 768
        Binary Search bounds = 768 - 1023
     * If the bounds would exceed the length of the array, then the startIndex is
     * rounded to zero. I.e, in the above, if the size were only 100, then startIndex
     * would be zero, resulting in a bounds of 0-100. Can be thought of as greedy up to
     * indexDelta size.
    */
    function getStartingIndex(History storage history, uint256 indexDelta) internal view returns (uint256) {
        uint256 length = history._checkpoints.length;

        if (indexDelta > length) return 0;
        return length - indexDelta;
    }
}
