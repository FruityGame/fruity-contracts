// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/auth/authorities/RolesAuthority.sol";
import "src/slots/jackpot/proxy/ExternalJackpotResolver.sol";
import "test/mocks/slots/jackpot/MockLocalJackpotResolver.sol";

contract MockExternalJackpotResolver is ExternalJackpotResolver, MockLocalJackpotResolver, RolesAuthority {
    constructor(uint256 max) RolesAuthority(msg.sender, this) ExternalJackpotResolver(max) {}
}