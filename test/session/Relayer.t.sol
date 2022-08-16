// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { MockERC20Proxy } from "test/mocks/tokens/MockERC20Proxy.sol";

contract RelayerTest is Test {
    receive() external payable {}
    fallback() external payable {}

    MockERC20Proxy token;

    event SessionCreated(address indexed owner);
    event SessionRefreshed(address indexed owner);
    event SessionEnded(address indexed owner);

    uint256 immutable proxyKey = 123;
    address immutable testUser = address(0xDEADBEEF);
    address immutable testUserProxy = vm.addr(123);

    function setUp() public virtual {
        token = new MockERC20Proxy(0);
    }

    function createProxyTransferMessage(
        address from,
        address to,
        uint256 amount,
        address proxyAddress
    ) internal view returns (bytes32 messageHash) {
        bytes memory message = abi.encode(
            token.TRANSFER_PROXY_TYPEHASH(),
            from,
            to,
            amount,
            proxyAddress,
            token.proxyNonces(proxyAddress)
        );

        messageHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(message)
                )
            );
    }

    function createProxyEndSessionMessage(
        address user,
        address proxyAddress
    ) internal view returns (bytes32 messageHash) {
        bytes memory message = abi.encode(
            token.END_SESSION_TYPEHASH(),
            user,
            proxyAddress,
            token.proxyNonces(proxyAddress)
        );

        messageHash =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(message)
                )
            );
    }

    function testCreateSession() public {
        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        vm.expectEmit(true, false, false, true);
        emit SessionCreated(testUser);
        token.createSession(testUserProxy, uint16(150));

        MockERC20Proxy.Session memory session = token.getSession(testUser);

        assertEq(session.proxy, testUserProxy);
        assertEq(session.sessionLength, uint16(150));
        assertEq(session.expiryBlock, uint64(block.number + 150));
    }

    function testCreateSessionOverwrite() public {
        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // Roll forward 10 blocks
        vm.roll(10);

        // Register the Proxy Key with the user's account
        // (This works because we've not used the Proxy Key to send any messages yet)
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        MockERC20Proxy.Session memory session = token.getSession(testUser);

        assertEq(session.proxy, testUserProxy);
        assertEq(session.sessionLength, uint16(150));
        assertEq(session.expiryBlock, uint64(block.number + 150));
    }

    function testCreateSessionProxyAddressZero() public {
        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        vm.expectRevert("Invalid Proxy Address provided");
        token.createSession(address(0), uint16(150));
    }

    function testTransferProxy() public {
        // Setup the user with some funds
        token.mintExternal(testUser, 1e18);

        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // Create a Proxy Transfer request to transfer the user's funds to our test account
        bytes32 messageHash = createProxyTransferMessage(
            testUser,
            address(this),
            1e18,
            testUserProxy
        );

        // Sign the Proxy Transfer request with the Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proxyKey, messageHash);

        // Roll forward 10 blocks, so we can verify the session expiryBlock gets updated
        vm.roll(10);

        // Send the Proxy Transfer request (can be done using any account)
        vm.expectEmit(true, false, false, true);
        emit SessionRefreshed(testUser);
        token.transferProxy(testUser, address(this), 1e18, v, r, s);

        // Ensure balances have been accredited
        assertEq(token.balanceOf(testUser), 0);
        assertEq(token.balanceOf(address(this)), 1e18);

        // Ensure expiryBlock has been refreshed/updated
        assertEq(token.getSession(testUser).expiryBlock, block.number + 150);
    }

    function testTransferProxyInvalidKey() public {
        // Setup the user with some funds
        token.mintExternal(testUser, 1e18);

        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // Create a Proxy Transfer request to transfer the user's funds to our test account
        bytes32 messageHash = createProxyTransferMessage(
            testUser,
            address(this),
            1e18,
            testUserProxy
        );

        // Sign the Proxy Transfer request with an incorrect Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(456, messageHash);

        // Attempt to send the Proxy transfer
        vm.expectRevert("Invalid Proxy Signature");
        token.transferProxy(testUser, address(this), 1e18, v, r, s);

        // Ensure no funds have been transfered
        assertEq(token.balanceOf(testUser), 1e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferProxyInvalidMessage() public {
        // Setup the user with some funds
        token.mintExternal(testUser, 1e18);

        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // Create a Proxy Transfer request with an invalid proxyAddress
        bytes32 messageHash = createProxyTransferMessage(
            testUser,
            address(this),
            1e18,
            address(0xD00FDAAF)
        );

        // Sign the Proxy Transfer request with the Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proxyKey, messageHash);

        // Attempt to send the Proxy transfer
        vm.expectRevert("Invalid Proxy Signature");
        token.transferProxy(testUser, address(this), 1e18, v, r, s);

        // Change the message to be valid
        messageHash = createProxyTransferMessage(
            testUser,
            address(this),
            1e18,
            testUserProxy
        );

        // Attempt to send the Proxy transfer with a different receiver
        vm.expectRevert("Invalid Proxy Signature");
        token.transferProxy(testUser, address(0xD00FDAAF), 1e18, v, r, s);

        // Attempt to send the Proxy transfer with a different sender
        vm.prank(address(0xD00FDAAF));
        token.createSession(vm.addr(456), uint16(150));

        vm.expectRevert("Invalid Proxy Signature");
        token.transferProxy(address(0xD00FDAAF), address(this), 1e18, v, r, s);

        // Ensure no funds have been transfered
        assertEq(token.balanceOf(testUser), 1e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferProxyExpiredSession() public {
        // Setup the user with some funds
        token.mintExternal(testUser, 1e18);

        // Register the Proxy Key with the user's account,
        // with a session that will immediately expire
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(0));

        // Create a Proxy Transfer request to transfer the user's funds to our test account
        bytes32 messageHash = createProxyTransferMessage(
            testUser,
            address(this),
            1e18,
            testUserProxy
        );

        // Sign the Proxy Transfer request with the Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proxyKey, messageHash);

        // Ensure the session has expired
        vm.expectRevert("Proxy Session does not exist");
        token.transferProxy(testUser, address(this), 1e18, v, r, s);

        // Ensure no funds have been transfered
        assertEq(token.balanceOf(testUser), 1e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testEndSession() public {
        // Setup the user with some funds
        token.mintExternal(testUser, 1e18);

        // Register the Proxy Key with the user's account
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // End their session
        vm.prank(testUser);
        vm.expectEmit(true, false, false, true);
        emit SessionEnded(testUser);
        token.endSession();

        // Ensure expiryBlock has been zeroed
        assertEq(token.getSession(testUser).expiryBlock, 0);

        // Create a Proxy Transfer request to transfer the user's funds to our test account
        bytes32 messageHash = createProxyTransferMessage(
            testUser,
            address(this),
            1e18,
            testUserProxy
        );

        // Sign the Proxy Transfer request with the Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proxyKey, messageHash);

        // Send the Proxy Transfer request (can be done using any account)
        vm.expectRevert("Proxy Session does not exist");
        token.transferProxy(testUser, address(this), 1e18, v, r, s);

        // Ensure no funds have been transfered
        assertEq(token.balanceOf(testUser), 1e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testEndSessionInvalidSession() public {
        // Attempt to end a session for our user that doesn't exist
        vm.expectRevert("Proxy Session does not exist");
        vm.prank(testUser);
        token.endSession();
    }

    function testEndSessionProxy() public {
        // Create a session as the test user
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // Create a Proxy End Session request to end the testUser's session
        bytes32 messageHash = createProxyEndSessionMessage(
            testUser,
            testUserProxy
        );

        // Sign the Proxy End Session request with the Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proxyKey, messageHash);

        // Send the Proxy End Session request
        token.endSessionProxy(testUser, v, r, s);

        // Ensure expiryBlock has been zeroed
        assertEq(token.getSession(testUser).expiryBlock, 0);
    }

    function testEndSessionProxyInvalidKey() public {
        // Create a session as the test user
        vm.prank(testUser);
        token.createSession(testUserProxy, uint16(150));

        // Create a Proxy End Session request to end the testUser's session
        bytes32 messageHash = createProxyEndSessionMessage(
            testUser,
            testUserProxy
        );

        // Sign the Proxy End Session request an incorrect Proxy key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(456, messageHash);

        // Send the Proxy End Session request
        vm.expectRevert("Invalid Proxy Signature");
        token.endSessionProxy(testUser, v, r, s);

        // Ensure expiryBlock has not been changed
        assertEq(token.getSession(testUser).expiryBlock, uint64(block.number + 150));
    }
}