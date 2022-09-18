// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { ECDSA } from "src/libraries/crypto/ECDSA.sol";
import { AbstractProxy } from "src/proxy/AbstractProxy.sol";
import { Certificates } from "src/libraries/crypto/Certificates.sol";
import { ProxyRelayer } from "src/proxy/ProxyRelayer.sol";

import { MockERC20 } from "test/mocks/tokens/MockERC20.sol";
import { MockProxyReceiver } from "test/mocks/proxy/MockProxyReceiver.sol";

contract ProxyReceiverTest is Test {
    receive() external payable {}
    fallback() external payable {}

    MockERC20 token;
    MockProxyReceiver receiver;
    ProxyRelayer relayer;

    uint256 immutable proxyKey = 123;
    address immutable proxyUser = vm.addr(123);

    uint256 immutable testKey = 456;
    address immutable testUser = vm.addr(456);

    function setUp() public virtual {
        token = new MockERC20(0);
        relayer = new ProxyRelayer(address(this), token, 1e18);
        receiver = new MockProxyReceiver();

        relayer.authorizeProxyReceiver(address(receiver), true);

        // Setup testUser with 10 Tokens
        token.mintExternal(testUser, 10e18);

        vm.prank(testUser);
        token.approve(address(relayer), 10e18);
    }

    function createSignedExecuteProxyMessage(
        address target,
        bytes memory _calldata,
        uint256 nonce,
        bytes32 domainSeparator
    ) internal returns (bytes32, bytes32) {
        bytes memory message = abi.encode(
            receiver.EXECUTE_PROXY_TYPEHASH(),
            target,
            _calldata,
            nonce
        );

        bytes32 messageHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    domainSeparator,
                    keccak256(message)
                )
            );

        return signAndCompress(proxyKey, messageHash);
    }

    function createSignedSessionMessage(
        address user,
        address proxy,
        uint192 expiry,
        uint256 nonce
    ) internal returns (bytes32, bytes32) {
        bytes memory message = abi.encode(
            relayer.SESSION_TYPEHASH(),
            user,
            proxy,
            expiry,
            nonce
        );

        bytes32 messageHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    relayer.DOMAIN_SEPARATOR(),
                    keccak256(message)
                )
            );

        return signAndCompress(testKey, messageHash);
    }

    function createSessionCertificate(
        address user,
        address proxy,
        uint192 expiry,
        uint256 nonce
    ) internal returns (bytes32, bytes32, uint256, uint256) {
        // Setup a session message
        (bytes32 rCert, bytes32 vsCert) = createSignedSessionMessage(
            user,
            proxy,
            expiry,
            nonce
        );

        // Compress the Session Certificate
        (uint256 certLhs, uint256 certRhs) = Certificates.compress(testUser, proxyUser, expiry);

        return (rCert, vsCert, certLhs, certRhs);
    }

    function signAndCompress(uint256 key, bytes32 messageHash) internal
    returns (bytes32 _r, bytes32 _vs) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, messageHash);
        (_r, _vs) = ECDSA.compress(v, r, s);
    }

    function testExecuteProxyMessage() public {
        uint192 expiry = 250;
        // Setup a session message
        (bytes32 rCert, bytes32 vsCert, uint256 certLhs, uint256 certRhs) = createSessionCertificate(
            testUser,
            proxyUser,
            expiry,
            relayer.sessionNonces(testUser) + 1
        );

        // Register our session with the Session Manager
        vm.prank(testUser);
        relayer.startSession(proxyUser, expiry, rCert, vsCert);

        // Create a message to execute the `mockExecute` method on MockProxyReceiver
        bytes memory _calldata = abi.encodeWithSelector(MockProxyReceiver.mockExecute.selector, 10);
        (bytes32 rProxy, bytes32 vsProxy) = createSignedExecuteProxyMessage(
            address(receiver),
            _calldata,
            receiver.userNonces(testUser),
            receiver.DOMAIN_SEPARATOR()
        );

        // Execute the `mockExecute` method via the Proxy interface
        relayer.relay(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            address(receiver), _calldata
        );

        // Ensure the fee has been taken, and that the nonce count for execution from this relayer has incremented
        //assertEq(token.balanceOf(testUser), 10e18 - relayer.fee());
        //assertEq(token.balanceOf(address(receiver)), relayer.fee());
        //assertEq(receiver.userNonces(receiver.getNonceKey(testUser, proxyUser)), 1);
    }

    /*function testExecuteProxyMessageInvalidRelayer() public {
        // Setup a session message
        uint192 expiry = uint192(250);
        bytes32 sessionMessage = createSessionMessage(
            testUser,
            proxyUser,
            expiry,
            relayer.sessionNonces(testUser) + 1,
            relayer.SESSION_TYPEHASH()
        );
        (bytes32 rCert, bytes32 vsCert) = signAndCompress(testKey, sessionMessage);

        // Compress the Session Certificate
        (uint256 certLhs, uint256 certRhs) = Certificates.compress(testUser, proxyUser, expiry);

        // Register our session with the Session Manager
        vm.prank(testUser);
        relayer.startSession(proxyUser, expiry, rCert, vsCert);

        // Create a message to execute the `mockExecute` method on MockProxyReceiver
        bytes memory _calldata = abi.encodeWithSelector(MockProxyReceiver.mockExecute.selector, 10);
        bytes32 executeProxyMessage = createExecuteProxyMessage(
            address(this),
            address(receiver),
            _calldata,
            receiver.userNonces(receiver.getNonceKey(testUser, proxyUser)),
            receiver.DOMAIN_SEPARATOR()
        );

        // Sign the executeProxyMessage with the Proxy Key
        (bytes32 rProxy, bytes32 vsProxy) = signAndCompress(proxyKey, executeProxyMessage);

        // Attempt to execute the message as an invalid relayer
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidRelayer.selector, address(this)));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );

        // Ensure the fee hasn't been taken
        assertEq(token.balanceOf(testUser), 10e18);
    }

    function testExecuteProxyInvalidCertificateParams() public {
        // Setup a Session that expires in 5 blocks
        uint192 expiry = uint192(5);
        bytes32 sessionMessage = createSessionMessage(
            testUser,
            proxyUser,
            expiry,
            relayer.sessionNonces(testUser) + 1,
            relayer.SESSION_TYPEHASH()
        );
        (bytes32 rCert, bytes32 vsCert) = signAndCompress(testKey, sessionMessage);

        // Compress the Session Certificate with an invalid User Address, address(0)
        (uint256 certLhs, uint256 certRhs) = Certificates.compress(address(0), proxyUser, expiry);

        // Register our session with the Session Manager
        vm.prank(testUser);
        relayer.startSession(proxyUser, expiry, rCert, vsCert);

        // Register ourselves as a valid Relayer in the Session Manager
        relayer.addRelayer(address(this));

        // Create a message to execute the `mockExecute` method on MockProxyReceiver
        bytes memory _calldata = abi.encodeWithSelector(MockProxyReceiver.mockExecute.selector, 10);
        bytes32 executeProxyMessage = createExecuteProxyMessage(
            address(this),
            address(receiver),
            _calldata,
            receiver.userNonces(receiver.getNonceKey(testUser, proxyUser)),
            receiver.DOMAIN_SEPARATOR()
        );

        // Sign the executeProxyMessage with the Proxy Key
        (bytes32 rProxy, bytes32 vsProxy) = signAndCompress(proxyKey, executeProxyMessage);

        // Attempt to execute the message with an invalid User Address, will cause
        // the expand() method of Certificates to deserialize a user with address(0)
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSession.selector, address(0)));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );

        // Compress the Session Certificate with an invalid Proxy Address, address(0)
        (certLhs, certRhs) = Certificates.compress(testUser, address(0), expiry);

        // Attempt to execute the message with an invalid Proxy Address
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSession.selector, testUser));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );

        // Roll forward beyond the expiry
        vm.roll(expiry + 1);

        // Compress the Session Certificate with valid addresses
        (certLhs, certRhs) = Certificates.compress(testUser, proxyUser, expiry);

        // Attempt to execute the message with an expired Session
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSession.selector, testUser));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );
    }

    function testExecuteProxyInvalidCertificateSignature() public {
        // Setup a session message
        uint192 expiry = uint192(250);
        bytes32 sessionMessage = createSessionMessage(
            testUser,
            proxyUser,
            expiry,
            relayer.sessionNonces(testUser) + 1,
            relayer.SESSION_TYPEHASH()
        );
        (bytes32 rCert, bytes32 vsCert) = signAndCompress(testKey, sessionMessage);

        // Register our session with the Session Manager
        vm.prank(testUser);
        relayer.startSession(proxyUser, expiry, rCert, vsCert);

        // Register ourselves as a valid Relayer in the Session Manager
        relayer.addRelayer(address(this));

        // Create a message to execute the `mockExecute` method on MockProxyReceiver
        bytes memory _calldata = abi.encodeWithSelector(MockProxyReceiver.mockExecute.selector, 10);
        bytes32 executeProxyMessage = createExecuteProxyMessage(
            address(this),
            address(receiver),
            _calldata,
            receiver.userNonces(receiver.getNonceKey(testUser, proxyUser)),
            receiver.DOMAIN_SEPARATOR()
        );

        // Sign the executeProxyMessage with the Proxy Key
        (bytes32 rProxy, bytes32 vsProxy) = signAndCompress(proxyKey, executeProxyMessage);

        // Compress the Session Certificate with an Invalid User (does not match signed message)
        (uint256 certLhs, uint256 certRhs) = Certificates.compress(address(this), proxyUser, expiry);

        // Test executing with an Invalid User
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, address(this)));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );

        // Compress the Session Certificate with an Invalid Proxy Address (does not match signed message)
        (certLhs, certRhs) = Certificates.compress(testUser, address(this), expiry);

        // Test executing with an Invalid Proxy
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testUser));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );

        // Compress the Session Certificate with an Invalid Expiry (does not match signed message)
        (certLhs, certRhs) = Certificates.compress(testUser, proxyUser, 5);

        // Test executing with an Invalid Expiry
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testUser));
        receiver.executeProxy(
            rCert, vsCert, certLhs, certRhs, // Certificate details
            rProxy, vsProxy, // Proxy Signature
            _calldata
        );
    }*/
}