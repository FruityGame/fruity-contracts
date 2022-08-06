// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/auth/authorities/RolesAuthority.sol";
import "src/payment/proxy/ExternalPaymentProcessor.sol";
import "test/mocks/payment/MockPaymentProcessor.sol";

contract MockExternalPaymentProcessor is ExternalPaymentProcessor, MockPaymentProcessor, RolesAuthority {
    modifier canAfford(uint256 payoutWad) override {
        _;
    }

    constructor() RolesAuthority(msg.sender, this) {}
}