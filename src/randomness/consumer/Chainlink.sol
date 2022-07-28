// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import "src/randomness/Beacon.sol";

struct VRFParams {
    address coordinator;
    address link;
    bytes32 keyHash;
    uint64 subscriptionId;
}

abstract contract RandomnessConsumer is Beacon, VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface private immutable coordinator;
    LinkTokenInterface private immutable link;

    bytes32 private immutable keyHash;
    uint64 private immutable subscriptionId;

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