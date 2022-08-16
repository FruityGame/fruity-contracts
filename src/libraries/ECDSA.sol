// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library ECDSA {
    // Mask to pluck the Most Significant Bit from _vs for EIP-2098
    bytes32 constant internal S_MASK = bytes32(uint256(1 << 255) - 1);

    error InvalidSignatureV(uint8 v);
    error InvalidSignatureS(bytes32 s);

    // Compress an Ethereum signature in accordance to EIP-2098
    function compress(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes32 _r, bytes32 _vs) {
        if (v != 27 && v != 28) revert InvalidSignatureV(v);
        if (s >> 255 != bytes32(0)) revert InvalidSignatureS(s);

        _r = r;
        _vs = (s & S_MASK) | bytes32(uint256(28 - v ^ 1) << 255);
    }

    // Unpack an EIP-2098 Ethereum signature in accordance to EIP-2098
    function expand(bytes32 r, bytes32 vs) internal pure returns (uint8 _v, bytes32 _r, bytes32 _s) {
        // Safe to cast here because we're only plucking one bit
        _v = uint8(uint256(vs >> 255)) + 27;
        _r = r;
        _s = vs & S_MASK;
    }
}