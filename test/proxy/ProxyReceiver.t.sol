// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { ECDSA } from "src/libraries/ECDSA.sol";
import { IProxy } from "src/proxy/IProxy.sol";
import { Certificates } from "src/libraries/Certificates.sol";
import { SessionRegistry } from "src/proxy/SessionRegistry.sol";

import { MockERC20 } from "test/mocks/tokens/MockERC20.sol";
import { MockProxyReceiver } from "test/mocks/proxy/MockProxyReceiver.sol";

contract ProxyReceiverTest is Test {
    receive() external payable {}
    fallback() external payable {}

    MockERC20 token;
    MockProxyReceiver receiver;
    SessionRegistry sessionRegistry;

    uint256 immutable proxyKey = 123;
    address immutable proxyUser = vm.addr(123);

    uint256 immutable testKey = 456;
    address immutable testUser = vm.addr(456);

    function setUp() public virtual {
        sessionRegistry = new SessionRegistry(1e18);

        token = new MockERC20(0);
        receiver = new MockProxyReceiver(token, sessionRegistry);

        token.mintExternal(testUser, 10e18);

        vm.prank(testUser);
        token.approve(address(receiver), 10e18);
    }

    function createExecuteProxyMessage(
        address target,
        address proxy,
        bytes memory _calldata,
        uint256 nonce
    ) internal view returns (bytes32 messageHash) {
        bytes memory message = abi.encode(
            receiver.EXECUTE_PROXY_TYPEHASH(),
            target,
            _calldata,
            nonce
        );

        messageHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    receiver.DOMAIN_SEPARATOR(),
                    keccak256(message)
                )
            );
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
    returns (bytes32 _r, bytes32 _vs) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(testKey, messageHash);
        (_r, _vs) = ECDSA.compress(v, r, s);
    }

    function testExecuteProxyMessage() public {
        // Setup a session message
        uint192 expiry = uint192(250);
        bytes32 sessionMessage = createSessionMessage(testUser, proxyUser, expiry);
        (bytes32 r, bytes32 vs) = signAndCompress(testKey, sessionMessage);
        // Setup a session message
        /*(uint8 v, bytes32 r, bytes32 s) = vm.sign(testKey, sessionMessage);
        (,bytes32 vs) = ECDSA.compress(v, r, s);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(proxyKey, executeProxyMessage);
        (,bytes32 vs2) = ECDSA.compress(v2, r2, s2);

        (uint256 lhs, uint256 rhs) = Certificates.compress(testUser, proxyUser, uint192(250));

        sessionMessage = createSessionMessage(
            testUser,
            proxyUser,
            uint192(250)
        );
    
        executeProxyMessage = createExecuteProxyMessage(
            address(receiver),
            proxyUser,
            __calldata,
            receiver.userNonces(receiver.getNonceKey(testUser, proxyUser))
        );

        receiver.executeProxy(
            r, vs, lhs, rhs,
            r2, vs2,
            __calldata
        );*/

        //receiver.executeProxy(IProxy.Session(r, vs, testUser, proxyUser, uint192(250)), __calldata, r2, vs2);
        //relayer.executeProxy(address(this), address(receiver), __calldata, r, vs);
        
        //relayer.verifySession(testUser);

        //receiver.claimFee(testUser, proxyUser);
    }
}