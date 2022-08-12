// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract MockChainlinkVRF is VRFCoordinatorV2Interface {
    uint256 public requestId = 0;
    address request;

    function fulfill(uint256 _requestId, uint256 randomness) external {
        uint256[] memory words = new uint256[](1);
        words[0] = randomness;

        (bool success, ) = request.call(
            abi.encodeWithSelector(VRFConsumerBaseV2.rawFulfillRandomWords.selector, _requestId, words)
        );

        require(success, "VRF Callback failed");
    }

    function requestRandomWords(
        bytes32,
        uint64,
        uint16,
        uint32,
        uint32
    )
        external override returns (uint256)
    {
        request = msg.sender;
        return requestId += 1;
    }

    function acceptSubscriptionOwnerTransfer(uint64) external override {}
    function addConsumer(uint64, address) external override {}
    function cancelSubscription(uint64, address) external override {}
    function createSubscription() external override returns (uint64) { return 0; }
    function getRequestConfig() external override view returns (
        uint16, uint32, bytes32[] memory bytesArray
    ) {
        bytesArray[0] = bytes32(0);
        return (uint16(0), uint32(0), bytesArray);
    }
    function getSubscription(uint64) external override view returns (
      uint96, uint64, address, address[] memory addresses
    ) {
        addresses[0] = address(0);
        return (uint96(0), uint64(0), address(0), addresses);
    }
    function pendingRequestExists(uint64) external override view returns (bool) { return false; }
    function removeConsumer(uint64, address) external override {}
    function requestSubscriptionOwnerTransfer(uint64, address) external override {}
}