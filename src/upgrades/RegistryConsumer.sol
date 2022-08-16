// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { AddressRegistry } from "src/upgrades/AddressRegistry.sol";

abstract contract RegistryConsumer {
    bytes32 constant public GOVERNOR_ROLE = keccak256(bytes("GOVERNOR"));
    bytes32 constant public RELAYER_ROLE = keccak256(bytes("RELAYER"));

    AddressRegistry public registry;
    mapping(bytes32 => address) public contracts;

    event ContractAddressChanged(bytes32 indexed contractType, address oldAddress, address newAddress);

    error InvalidAddress(bytes32 role, address _address);

    constructor(AddressRegistry _registry) {
        registry = _registry;
    }

    // Poll the registry for the current address of the Contract with type `type`,
    // updating the local copy of the contract address if it finds it
    function pollRegistry(bytes32 role) public {
        // Saves multiple SLOADs
        address oldAddress = contracts[role];
        if (oldAddress == address(0)) revert InvalidAddress(role, oldAddress);

        // Saves multiple calls to AddressRegistry
        address newAddress = registry.contracts(role);
        if (newAddress == address(0)) revert InvalidAddress(role, newAddress);

        // If the Address Registry has a new address registered for this type
        if (oldAddress != newAddress) {
            contracts[role] = newAddress;
            _contractChanged(role, oldAddress, newAddress);
            emit ContractAddressChanged(role, oldAddress, newAddress);
        }
    }

    function _contractChanged(bytes32 role, address oldAddress, address newAddress) internal virtual;
}