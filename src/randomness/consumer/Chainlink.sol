// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { LinkTokenInterface } from "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import { VRFCoordinatorV2Interface } from "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import { VRFConsumerBaseV2 } from "chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import { RandomnessBeacon } from "src/randomness/RandomnessBeacon.sol";

abstract contract ChainlinkConsumer is RandomnessBeacon, VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface private immutable coordinator;
    LinkTokenInterface private immutable link;

    bytes32 private immutable keyHash;
    uint64 private immutable subscriptionId;

    struct VRFParams {
        address coordinator;
        address link;
        bytes32 keyHash;
        uint64 subscriptionId;
    }

    constructor(
        VRFParams memory params
    )
        VRFConsumerBaseV2(params.coordinator)
    {
        coordinator = VRFCoordinatorV2Interface(params.coordinator);
        link = LinkTokenInterface(params.link);
        keyHash = params.keyHash;
        subscriptionId = params.subscriptionId;
    }

    function requestRandomness() internal override returns (uint256) {
        return coordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            3,
            1000000,
            1
        );
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        fulfillRandomness(requestId, randomWords[0]);
    }

    // TODO: Top up function
}