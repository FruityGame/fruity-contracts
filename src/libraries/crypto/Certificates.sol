// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library Certificates {
    uint256 constant internal ADDRESS_MASK = uint256(1 << 160) - 1;

    function compress(address user, address proxy, uint192 expiry) internal pure returns (uint256 lhs, uint256 rhs) {
        // Pack 64 Bits of Proxy Address and 160 bits of User address in LHS
        lhs = uint256(uint160(proxy)) << 160 | uint160(user);
        // Pack 192 Bits of Expiry and 96 Bits of Proxy address in RHS
        rhs = (uint256(expiry) << 64) | uint160(proxy) >> 96;
    }

    function expand(uint256 lhs, uint256 rhs) internal pure returns (address user, address proxy, uint256 expiry) {
        // Mask out 160 Bits of user address
        user = address(uint160(lhs & ADDRESS_MASK));
        // Shift RHS to get 96 Bits and LHS to get 64 Bits of Proxy Address
        proxy = address(uint160( rhs << 96 | lhs >> 160 ));
        // Shift RHS 64 Bits to get 192 Bits of Expiry
        expiry = rhs >> 64;
    }
}