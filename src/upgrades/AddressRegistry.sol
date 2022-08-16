// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Auth } from "solmate/auth/Auth.sol";

abstract contract AddressRegistry is Auth {
    mapping(bytes32 => address) public contracts;

    function setContractAddress(bytes32 role, address contractAddress) external requiresAuth() {
        contracts[role] = contractAddress;
    }
}