// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/randomness/RandomnessBeacon.sol";

abstract contract MockVRF is RandomnessBeacon {
    uint256 requestId = 0;

    constructor() {}

    function requestRandomness() internal override returns (uint256) {
        return requestId++;        
    }

    function fulfillRandomnessExternal(uint256 id, uint256 randomness) external {
        fulfillRandomness(id, randomness);
    }
}