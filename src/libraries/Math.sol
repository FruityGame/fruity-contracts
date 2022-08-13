// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library Math {
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a & b) + (a ^ b) / 2;
    }

    function difference(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function larger(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function smaller(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}