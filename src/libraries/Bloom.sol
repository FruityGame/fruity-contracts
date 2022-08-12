// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library Bloom {
    function encode(bytes32 item, uint256 index) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(item, index))) % 256;
    }

    function check(uint256 filter, bytes32 item, uint256 index) internal pure returns (uint256) {
        uint256 position = encode(item, index);
        return (filter & (1 << position)) >> position;
    }

    function insert(uint256 filter, bytes32 item) internal pure returns (uint256) {
        filter |= (1 << encode(item, 0));
        filter |= (1 << encode(item, 1));
        filter |= (1 << encode(item, 2));
        filter |= (1 << encode(item, 3));
        filter |= (1 << encode(item, 4));
        filter |= (1 << encode(item, 5));
        filter |= (1 << encode(item, 6));
        filter |= (1 << encode(item, 7));

        return filter;
    }

    function insertChecked(uint256 filter, bytes32 item) internal pure returns (uint256 out) {
        out = insert(filter, item);
        require(filter != out, "Duplicate item detected");
    }

    function contains(uint256 filter, bytes32 item) internal pure returns (bool) {
        return filter == insert(filter, item);
    }

    function containsWithConfidence(uint256 filter, bytes32 item) internal pure returns (uint256 confidence) {
        confidence = check(filter, item, 0);
        confidence += check(filter, item, 1);
        confidence += check(filter, item, 2);
        confidence += check(filter, item, 3);
        confidence += check(filter, item, 4);
        confidence += check(filter, item, 5);
        confidence += check(filter, item, 6);
        confidence += check(filter, item, 7);

        return (confidence * 100**2) / 800;
    }
}