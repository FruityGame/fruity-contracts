// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract MockChainlinkVRF is VRFCoordinatorV2Interface {
    uint256 requestId = 0;
    address request;

    function fulfill(uint256 randomness) external {
        VRFConsumerBaseV2 base;
        request.call(
            abi.encodeWithSelector(base.rawFulfillRandomWords.selector, requestId, [randomness])
        );
    }

    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    )
        external override returns (uint256)
    {
        request = msg.sender;
        return requestId += 1;
    }

    function getLatestRequestId() public view returns (uint256) {
        return requestId;
    }

    function acceptSubscriptionOwnerTransfer(uint64 subId) external override {}
    function addConsumer(uint64 subId, address consumer) external override {}
    function cancelSubscription(uint64 subId, address to) external override {}
    function createSubscription() external override returns (uint64 subId) { return 0; }
    function getRequestConfig() external override view returns (
        uint16, uint32, bytes32[] memory bytesArray
    ) {
        bytesArray[0] = bytes32(0);
        return (uint16(0), uint32(0), bytesArray);
    }
    function getSubscription(uint64 subId) external override view returns (
      uint96, uint64, address, address[] memory addresses
    ) {
        addresses[0] = address(0);
        return (uint96(0), uint64(0), address(0), addresses);
    }
    function pendingRequestExists(uint64 subId) external override view returns (bool) { return false; }
    function removeConsumer(uint64 subId, address consumer) external override {}
    function requestSubscriptionOwnerTransfer(uint64 subId, address newOwner) external override {}
}