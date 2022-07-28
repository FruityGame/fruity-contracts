// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/Slots.sol";

contract BasicSlots is Slots {
    constructor(
        VRFParams memory vrfParams,
        SlotParams memory params,
        uint8[] memory specialSymbols
    ) Slots (
        vrfParams,
        params,
        specialSymbols
    ) {}

    function takePayment(address user, uint256 totalBet) internal override {
        require(msg.value >= totalBet, "Amount provided not enough to cover bet");
    }

    function payout(address user, uint256 payoutWad) internal override returns (bool) {
        if (payoutWad > address(this).balance) payoutWad = address(this).balance;
        (bool success, ) = payable(user).call{value: payoutWad}("");
        return success;
    }

    function refund(address user, uint256 refundWad) internal override returns (bool) {
        require(address(this).balance >= refundWad, "Insufficient funds in contract to process refund");
        (bool success, ) = payable(user).call{value: refundWad}("");
        return success;
    }

    function resolveSpecialSymbols(uint256 symbol, uint256 count, uint256 board) internal override {}
}