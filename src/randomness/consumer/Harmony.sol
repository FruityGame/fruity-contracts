// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/randomness/Beacon.sol";

struct VRFParams {
    uint256 i;
}

abstract contract RandomnessConsumer is Beacon {
    constructor(VRFParams memory params){}

    function requestRandomness() internal override returns (uint256) {
        uint[1] memory bn;
        bn[0] = block.number;
        uint256 result;

        assembly {
            let memPtr := mload(0x40)
            if iszero(staticcall(not(0), 0xff, bn, 0x20, memPtr, 0x20)) {
                invalid()
            }
            result := mload(memPtr)
        }

        fulfillRandomness(1, result);
        return 1;
    }
}