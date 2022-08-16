// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";

import { MockAddressRegistry } from "test/mocks/upgrades/MockAddressRegistry.sol";

contract AddressRegistryTest is Test {
    MockAddressRegistry registry;

    function setUp() public virtual {
        registry = new MockAddressRegistry();        
    }
}