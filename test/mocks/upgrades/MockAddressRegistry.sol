// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";
import { AddressRegistry } from "src/upgrades/AddressRegistry.sol";
import { RegistryConsumer } from "src/upgrades/RegistryConsumer.sol";

contract MockAddressRegistry is AddressRegistry, RolesAuthority {
    constructor() RolesAuthority(msg.sender, this) {
        contracts[keccak256(bytes("GOVERNOR"))] = msg.sender;
        contracts[keccak256(bytes("RELAYER"))] = msg.sender;
    }
}