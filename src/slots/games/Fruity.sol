// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/MultiLineSlots.sol";
import "src/slots/jackpot/LocalJackpotResolver.sol";
import "src/payment/vault/ERC20VaultPaymentProcessor.sol";
import "src/randomness/consumer/Chainlink.sol";

contract Fruity is MultiLineSlots, LocalJackpotResolver, ERC20VaultPaymentProcessor, ChainlinkConsumer {
    mapping(uint256 => SlotSession) private sessions;

    constructor(
        address asset, string memory name, string memory symbol,
        VRFParams memory vrfParams
    )
        ChainlinkConsumer(vrfParams)
        ERC20VaultPaymentProcessor(asset, name, symbol)
        MultiLineSlots(getInitialParams(), getInitialWinlines())
    {}

    function getSession(uint256 betId) internal view override
    returns (SlotSession memory session) {
        session = sessions[betId];

        if (session.betWad == 0) revert InvalidSession(session.user, betId);
    }

    function startSession(uint256 betId, SlotSession memory session) internal override {
        if (session.betWad == 0) revert InvalidSession(session.user, betId);

        sessions[betId] = session;
    }

    function endSession(uint256 betId) internal override {
        if (sessions[betId].betWad == 0) revert InvalidSession(sessions[betId].user, betId);

        sessions[betId].betWad = 0;
    }

    // I hate this language so much
    function getInitialWinlines() private pure returns (uint256[] memory out) {
        out = new uint256[](20);
        out[0] = 341; out[1] = 682; out[2] = 1023; out[3] = 630; out[4] = 871;
        out[5] = 986; out[6] = 671; out[7] = 473; out[8] = 413; out[9] = 854;
        out[10] = 599; out[11] = 873; out[12] = 637; out[13] = 869; out[14] = 629;
        out[15] = 474; out[16] = 415; out[17] = 985; out[18] = 669; out[19] = 874;
    }

    function getInitialParams() private pure returns (SlotParams memory out) {
        out = SlotParams(3, 5, 6, 255, 255, 255, 115, 20, 5, 500, 1e15);
    }
}