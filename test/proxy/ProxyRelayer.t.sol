// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { ECDSA } from "src/libraries/crypto/ECDSA.sol";
import { Certificates } from "src/libraries/crypto/Certificates.sol";

import { EIP712 } from "src/mixins/EIP712.sol";
import { AbstractProxy } from "src/proxy/AbstractProxy.sol";
import { ProxyRelayer } from "src/proxy/ProxyRelayer.sol";

import { ProxyTest } from "test/proxy/ProxyTest.sol";

import { MockERC20 } from "test/mocks/tokens/MockERC20.sol";
import { MockProxyReceiver } from "test/mocks/proxy/MockProxyReceiver.sol";

contract TestProxyRelayer is ProxyTest {

    MockERC20 token;
    ProxyRelayer relayer;
    MockProxyReceiver receiver;

    uint256 immutable proxyKey = 123;
    address immutable proxyAddress = vm.addr(123);

    uint256 immutable testKey = 456;
    address immutable testAddress = vm.addr(456);

    event SessionStarted(address indexed user, address proxy, uint256 expiry);
    event SessionEnded(address indexed user, address proxy, uint256 expiry);

    // Test implements EIP712 to utilize the hashing functions built in
    constructor() EIP712("TestProxyRelayer", "1") {}

    function setUp() public virtual {
        token = new MockERC20(0);
        relayer = new ProxyRelayer(address(this), token, 1e18);
    }

    function testStartSession() public {
        uint192 expiry = 250;

        // Create a Session Message and sign it with our test user key
        (bytes32 r, bytes32 vs) = createSignedSessionMessage(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Start the Session
        vm.expectEmit(true, false, false, true);
        emit SessionStarted(testAddress, proxyAddress, expiry);
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, r, vs);

        assertEq(relayer.sessionNonces(testAddress), 1);

        // Recreate the session
        (bytes32 rNew, bytes32 vsNew) = createSignedSessionMessage(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Start the Session
        vm.expectEmit(true, false, false, true);
        emit SessionStarted(testAddress, proxyAddress, expiry);
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, rNew, vsNew);

        // Ensure the Session Nonces have been incremented, terminating all past Sessions
        assertEq(relayer.sessionNonces(testAddress), 2);

        // Ensure the old Session is invalid
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testAddress));
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, r, vs);

        // Ensure the Session Nonces haven't changed
        assertEq(relayer.sessionNonces(testAddress), 2);
    }

    function testStartSessionInvalidNonce() public {
        // Create a Session Message with an invalid nonce
        (bytes32 r, bytes32 vs) = createSignedSessionMessage(
            testAddress,
            proxyAddress,
            uint192(250),
            relayer.sessionNonces(testAddress),
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testAddress));
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, uint192(250), r, vs);

        assertEq(relayer.sessionNonces(testAddress), 0);
    }

    function testStartSessionInvalidProxy() public {
        // Create a Session Message with an invalid Proxy Address (address 0)
        (bytes32 r, bytes32 vs) = createSignedSessionMessage(
            testAddress,
            address(0),
            uint192(250),
            relayer.sessionNonces(testAddress),
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(abi.encodeWithSelector(ProxyRelayer.InvalidProxyAddress.selector, address(0)));
        vm.prank(testAddress);
        relayer.startSession(address(0), uint192(250), r, vs);

        // Ensure session nonces haven't been incremented
        assertEq(relayer.sessionNonces(testAddress), 0);
    }

    function testStartSessionInvalidExpiry() public {
        // Create a Session Message with an invalid expiry (expiry date in the past/on current block)
        (bytes32 r, bytes32 vs) = createSignedSessionMessage(
            testAddress,
            proxyAddress,
            uint192(1),
            relayer.sessionNonces(testAddress) + 1,
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(abi.encodeWithSelector(ProxyRelayer.InvalidExpiry.selector, uint192(1)));
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, uint192(1), r, vs);

        // Ensure session nonces haven't been incremented
        assertEq(relayer.sessionNonces(testAddress), 0);
    }

    function testEndSessionProxy() public {
        uint192 expiry = 250;

        // Create a Session Certificate
        (bytes32 rCert, bytes32 vsCert, uint256 certLhs, uint256 certRhs) = createSessionCertificate(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Create our session with our Session Certificate
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, rCert, vsCert);

        // Create an End Session via proxy message
        (bytes32 rProxy, bytes32 vsProxy) = createSignedEndSessionMessage(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress),
            proxyKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session with our self-signed cert and proxy key
        vm.expectEmit(true, false, false, true);
        emit SessionEnded(testAddress, proxyAddress, expiry);
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Ensure the session nonce has been incremented, terminating all past sessions
        assertEq(relayer.sessionNonces(testAddress), 2);

        // Create another valid End Session request with our Session and Proxy keys
        (rProxy, vsProxy) = createSignedEndSessionMessage(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            proxyKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session again, ensuring the session has been marked as invalid
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testAddress));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Ensure the Session Nonce hasn't been incremented
        assertEq(relayer.sessionNonces(testAddress), 2);
    }

    function testEndSessionProxyInvalidSessionCertificate() public {
        uint192 expiry = 250;

        // Create a Session Certificate
        (bytes32 rCert, bytes32 vsCert, uint256 certLhs, uint256 certRhs) = createSessionCertificate(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Create our session with our Session Certificate
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, rCert, vsCert);

        // Create a Session Certificate with testAddress = 0
        (rCert, vsCert, certLhs, certRhs) = createSessionCertificate(
            address(0),
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress),
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Create a valid End Session message
        (bytes32 rProxy, bytes32 vsProxy) = createSignedEndSessionMessage(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            proxyKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session with a Session Certificate that has an address of 0
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSession.selector, address(0)));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Create a Session Certificate with proxyAddress = 0
        (rCert, vsCert, certLhs, certRhs) = createSessionCertificate(
            testAddress,
            address(0),
            expiry,
            relayer.sessionNonces(testAddress),
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session with a Session Certificate that has a Proxy Address of 0
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSession.selector, testAddress));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Create a Session Certificate with an invalid Domain Seperator
        (rCert, vsCert, certLhs, certRhs) = createSessionCertificate(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress),
            testKey,
            DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session with a Session Certificate that has an invalid Domain Seperator
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testAddress));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Ensure the Session Nonce hasn't been incremented
        assertEq(relayer.sessionNonces(testAddress), 1);
    }

    function testEndSessionProxyInvalidProxyAddress() public {
        uint192 expiry = 250;

        // Create a Session Certificate
        (bytes32 rCert, bytes32 vsCert, uint256 certLhs, uint256 certRhs) = createSessionCertificate(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            testKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Create our session with our Session Certificate
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, rCert, vsCert);

        // Create an End Session via proxy message with an Invalid proxy address
        (bytes32 rProxy, bytes32 vsProxy) = createSignedEndSessionMessage(
            testAddress,
            address(0),
            expiry,
            relayer.sessionNonces(testAddress),
            proxyKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session with the Proxy Address set to address(0)
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, proxyAddress));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Create an End Session via proxy message with an Invalid user address
        (rProxy, vsProxy) = createSignedEndSessionMessage(
            address(0),
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress),
            proxyKey,
            relayer.DOMAIN_SEPARATOR()
        );

        // Attempt to end the Proxy Session with the User Address set to address(0)
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, proxyAddress));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);

        // Ensure the Session Nonce hasn't been incremented
        assertEq(relayer.sessionNonces(testAddress), 1);
    }

    /*function testEndSessionDirect() public {
        uint192 expiry = 250;

        // Create a Session Message
        bytes32 sessionMessage = createMessage(
            testAddress,
            proxyAddress,
            expiry,
            relayer.sessionNonces(testAddress) + 1,
            relayer.SESSION_TYPEHASH()
        );
        (bytes32 rCert, bytes32 vsCert) = signAndCompress(testKey, sessionMessage);

        // Create our session
        vm.prank(testAddress);
        relayer.startSession(proxyAddress, expiry, rCert, vsCert);

        // End our session
        vm.prank(testAddress);
        relayer.endSession();

        // Ensure the Session Nonce has been incremented
        assertEq(relayer.sessionNonces(testAddress), 2);

        // Attempt to reuse the ended Session to end itself again
        // Ensuring the Session has been invalidated

        // Create a valid End Session via proxy message
        bytes32 endSessionMessage = createMessage(
            testAddress,
            proxyAddress,
            uint192(250),
            relayer.sessionNonces(testAddress) + 1,
            relayer.END_SESSION_TYPEHASH()
        );
        (bytes32 rProxy, bytes32 vsProxy) = signAndCompress(proxyKey, endSessionMessage);
    
        // Compile a packed Session Certificate
        (uint256 certLhs, uint256 certRhs) = Certificates.compress(testAddress, proxyAddress, uint192(250));

        // Attempt to end the Session using our Session Key, the Session should no longer be valid
        vm.expectRevert(abi.encodeWithSelector(AbstractProxy.InvalidSignature.selector, testAddress));
        relayer.endSessionProxy(rCert, vsCert, certLhs, certRhs, rProxy, vsProxy);
    }

    function testRelay() public {

    }

    function testRelayUnauthorized() public {
        
    }

    function testRelayFailedExecution() public {

    }*/
}