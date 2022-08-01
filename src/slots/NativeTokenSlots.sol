// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/WETH.sol";
import "src/slots/BaseSlots.sol";

abstract contract NativeTokenSlots is BaseSlots {
    WETH private immutable native;

    constructor(
        SlotParams memory slotParams,
        VaultParams memory vaultParams,
        uint256[] memory winlines
    ) BaseSlots(slotParams, vaultParams, winlines) {
        native = WETH(payable(vaultParams.asset));
    }

    function placeBet(uint256 credits, uint256 winlines) public payable override returns (uint256 requestId) {
        super.placeBet(credits, winlines);
    }

    function payout(address user, uint256 payoutWad) internal override canAfford(payoutWad) {
        //native.withraw(payoutWad);
        (bool success, ) = payable(user).call{value: payoutWad}("");
        if (!success) revert PayoutError(user, payoutWad);
    }

    function refund(address user, uint256 refundWad) internal override canAfford(refundWad) {
        //native.withraw(refundWad);
        (bool success, ) = payable(user).call{value: refundWad}("");
        if (!success) revert RefundError(user, refundWad);
    }

    function takePayment(address user, uint256 paymentWad) internal override {
        if (msg.value < paymentWad) revert InsufficientFunds(msg.value, paymentWad);
        //native.deposit();
    }
}