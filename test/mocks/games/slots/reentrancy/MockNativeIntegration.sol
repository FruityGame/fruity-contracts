// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/upgrades/AddressRegistry.sol";
import "src/games/slots/SingleLineSlots.sol";

import "test/mocks/games/slots/jackpot/MockLocalJackpotResolver.sol";
import "src/payment/native/NativePaymentProcessor.sol";
import "test/mocks/MockVRF.sol";

// Sample integration with the NativePaymentProcessor, for testing reentrancy scenarios
contract MockNativeIntegration is SingleLineSlots, MockLocalJackpotResolver, NativePaymentProcessor, MockVRF {
    mapping(uint256 => SlotSession) public sessions;

    constructor(
        SlotParams memory slotParams,
        AddressRegistry registry
    )
        SingleLineSlots(slotParams, registry)
    {}

    function getSession(uint256 betId) internal view override
    returns (SlotSession memory session) {
        session = sessions[betId];

        if (session.betWad == 0) revert InvalidSession(msg.sender, betId);
    }

    function startSession(uint256 betId, SlotSession memory session) internal override {
        if (session.betWad == 0) revert InvalidSession(msg.sender, betId);

        sessions[betId] = session;
    }

    function endSession(uint256 betId) internal override {
        if (sessions[betId].betWad == 0) revert InvalidSession(msg.sender, betId);

        sessions[betId].betWad = 0;
    }
}

