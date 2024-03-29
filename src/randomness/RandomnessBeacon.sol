// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

abstract contract RandomnessBeacon {
    function requestRandomness() internal virtual returns (uint256);
    function fulfillRandomness(uint256 id, uint256 randomness) internal virtual;
}