// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import { ECDSA } from "src/libraries/ECDSA.sol";

contract ECDSATest is Test {
    function setUp() public virtual {}

    function testCompressInvalidS() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, bytes32("ABC"));

        // Corrupt the S point
        s |= bytes32((uint256(1) << 255));

        vm.expectRevert(abi.encodeWithSelector(ECDSA.InvalidSignatureS.selector, s));
        ECDSA.compress(v, r, s);
    }

    function testCompressInvalidVFuzz(uint8 v) public {
        if (v == 27 || v == 28) return;

        (, bytes32 r, bytes32 s) = vm.sign(1, bytes32("ABC"));

        vm.expectRevert(abi.encodeWithSelector(ECDSA.InvalidSignatureV.selector, v));
        ECDSA.compress(v, r, s);

        vm.expectRevert(abi.encodeWithSelector(ECDSA.InvalidSignatureV.selector, v));
        ECDSA.compress(v, r, s);
    }

    function testCompressExpand() public {
        bytes32 message = bytes32("ABC");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, bytes32("ABC"));
        (bytes32 _r, bytes32 vs) = ECDSA.compress(v, r, s);
        
        //address expected = ecrecover(message, v, r, s);
        (uint8 recoveredV, bytes32 recoveredR, bytes32 recoveredS) = ECDSA.expand(_r, vs);
        assertEq(recoveredV, v);
        assertEq(recoveredR, r);
        assertEq(recoveredS, s);
    }
}