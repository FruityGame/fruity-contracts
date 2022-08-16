// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";

import { AddressRegistry } from "src/upgrades/AddressRegistry.sol";
import { RegistryConsumer } from "src/upgrades/RegistryConsumer.sol";

abstract contract Game is RegistryConsumer, RolesAuthority {
    
    enum Roles {
        Governor,
        Relayer
    }

    error InvalidGovernorAddress(address _address);
    error InvalidRelayerAddress(address _address);

    constructor(AddressRegistry addressRegistry)
        RolesAuthority(address(this), this)
        RegistryConsumer(addressRegistry)
    {
        address governor = registry.contracts(GOVERNOR_ROLE);
        address relayer = registry.contracts(RELAYER_ROLE);

        if(governor == address(0)) revert InvalidGovernorAddress(governor);
        if(relayer == address(0)) revert InvalidRelayerAddress(relayer);

        // (note): setUserRole in the constructor is causing the EVM to revert for some reason
        getUserRoles[governor] |= bytes32(1 << uint8(Roles.Governor));
        getUserRoles[relayer] |= bytes32(1 << uint8(Roles.Relayer));
    }

    function _contractChanged(bytes32 role, address oldAddress, address newAddress) internal virtual override {
        if (role == GOVERNOR_ROLE) {
            setUserRole(oldAddress, uint8(Roles.Governor), false);
            setUserRole(newAddress, uint8(Roles.Governor), true);
            return;
        }

        if (role == RELAYER_ROLE) {
            setUserRole(oldAddress, uint8(Roles.Relayer), false);
            setUserRole(newAddress, uint8(Roles.Relayer), true);
            return;
        }
    }
}