// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { AddressRegistry } from "src/upgrades/AddressRegistry.sol";
import { SlotParams, SlotSession, MultiLineSlots } from "src/games/slots/MultiLineSlots.sol";
import { LocalJackpotResolver } from "src/games/slots/jackpot/LocalJackpotResolver.sol";
import { RemotePaymentProcessor } from "src/payment/external/RemotePaymentProcessor.sol";
import { ExternalPaymentProcessor } from "src/payment/external/ExternalPaymentProcessor.sol";
import { ChainlinkConsumer } from "src/randomness/consumer/Chainlink.sol";

contract Fruity is MultiLineSlots, LocalJackpotResolver, RemotePaymentProcessor, ChainlinkConsumer {
    mapping(uint256 => SlotSession) private sessions;

    modifier sanitizeParams(SlotParams memory _params) override {
        
        if (
            _params.rows != 3 || // Constants
            _params.reels != 5 ||
            _params.symbols != 6 ||
            _params.payoutConstant == 0 || // Configurables
            _params.maxBetCredits == 0 ||
            _params.maxJackpotCredits == 0 ||
            _params.creditSizeWad == 0
        ) revert InvalidParams();
        /*require(_params.wildSymbol == 255, "Invalid Param: wildSymbol");
        require(_params.scatterSymbol == 255, "Invalid Param: scatterSymbol");
        require(_params.bonusSymbol == 255, "Invalid Param: bonusSymbol");*/
        _;
    }

    constructor(
        ChainlinkConsumer.VRFParams memory vrfParams,
        ExternalPaymentProcessor externalPaymentProcessor,
        AddressRegistry addressRegistry
    )
        ChainlinkConsumer(vrfParams)
        RemotePaymentProcessor(externalPaymentProcessor)
        MultiLineSlots(getInitialParams(), addressRegistry, getInitialWinlines())
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

        // Apparently cheaper than assigning to 0
        delete sessions[betId].betWad;
    }

    // I hate this language so much
    function getInitialWinlines() private pure returns (uint256[] memory out) {
        out = new uint256[](20);
        out[0] = 341; out[1] = 682; out[2] = 1023; out[3] = 630; out[4] = 871;
        out[5] = 986; out[6] = 671; out[7] = 473; out[8] = 413; out[9] = 854;
        out[10] = 599; out[11] = 873; out[12] = 637; out[13] = 869; out[14] = 629;
        out[15] = 474; out[16] = 415; out[17] = 985; out[18] = 669; out[19] = 874;
    }

    function getInitialParams() private pure returns (SlotParams memory) {
        return SlotParams(3, 5, 6, 255, 255, 255, 115, 20, 5, 500, 1e15);
    }
}