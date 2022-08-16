// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { ECDSA } from "src/libraries/ECDSA.sol";
import { IProxy } from "src/proxy/IProxy.sol";
import { Certificates } from "src/libraries/Certificates.sol";
import { SessionRegistry } from "src/proxy/SessionRegistry.sol";

contract TestSessionRegistry is Test {
    SessionRegistry sessionRegistry;

    uint256 immutable proxyKey = 123;
    address immutable proxyUser = vm.addr(123);

    uint256 immutable testKey = 456;
    address immutable testUser = vm.addr(456);

    function setUp() public virtual {
        sessionRegistry = new SessionRegistry(1e18);
    }

    function createSessionMessage(
        address user,
        address proxy,
        uint192 expiry
    ) internal view returns (bytes32 messageHash) {
        bytes memory message = abi.encode(
            receiver.SESSION_TYPEHASH(),
            user,
            proxy,
            expiry
        );

        messageHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sessionRegistry.DOMAIN_SEPARATOR(),
                    keccak256(message)
                )
            );
    }

    function signAndCompress(uint256 key, bytes32 messageHash) internal
        returns (bytes32 _r, bytes32 _vs)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(testKey, messageHash);
        (_r, _vs) = ECDSA.compress(v, r, s);
    }

    function testRegisterSession() public {
        // Create a Session Message and sign it with our test user key
        
    }
}