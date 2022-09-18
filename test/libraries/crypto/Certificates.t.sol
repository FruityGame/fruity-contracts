
// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { Certificates } from "src/libraries/crypto/Certificates.sol";

contract SessionsTest is Test {
    function setUp() public virtual {}

    uint256 constant UINT160_MASK = (1 << 160) - 1;
    uint256 constant UINT192_MASK = (1 << 160) - 1;

    function testCompressFuzz(uint256 entropy) public {
        if (entropy == 0) return;

        address user1 = vm.addr((entropy ^ 123) & UINT160_MASK);
        address user2 = vm.addr((entropy ^ 456) & UINT160_MASK);
        uint192 expiry = uint192(entropy & UINT192_MASK);

        (uint256 lhs, uint256 rhs) = Certificates.compress(user1, user2, expiry);
        (address recoveredUser1, address recoveredUser2, uint256 recoveredExpiry) = Certificates.expand(lhs, rhs);

        assertEq(recoveredUser1, user1);
        assertEq(recoveredUser2, user2);
        assertEq(recoveredExpiry, recoveredExpiry);
    }
}