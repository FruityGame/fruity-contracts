// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import "src/randomness/Beacon.sol";

abstract contract RandomnessConsumer is Beacon, VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface private immutable coordinator;
    LinkTokenInterface private immutable link;

    bytes32 private immutable keyHash;
    uint64 private immutable subscriptionId;
    address private immutable owner;

    constructor(
        address _coordinator,
        address _link,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address _owner
    )
        VRFConsumerBaseV2(_coordinator)
    {
        coordinator = VRFCoordinatorV2Interface(_coordinator);
        link = LinkTokenInterface(_link);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        owner = _owner;
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
        //require(msg.sender == address(coordinator), "Invalid VRF fulfill request");
        fulfillRandomness(requestId, randomWords[0]);
    }

    // TODO: Top up function
}