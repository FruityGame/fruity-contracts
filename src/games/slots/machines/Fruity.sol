// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SlotParams, SlotSession, MultiLineSlots } from "src/games/slots/MultiLineSlots.sol";
import { LocalJackpotResolver } from "src/games/slots/jackpot/LocalJackpotResolver.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";
import { ChainlinkConsumer } from "src/randomness/consumer/Chainlink.sol";

contract Fruity is MultiLineSlots, LocalJackpotResolver, ERC20VaultPaymentProcessor, ChainlinkConsumer {
    mapping(uint256 => SlotSession) private sessions;

    modifier sanitizeParams(SlotParams memory _params) override {
        // Constants
        require(_params.rows == 3, "Invalid Param: rows");
        require(_params.reels == 5, "Invalid Param: reels");
        require(_params.symbols == 6, "Invalid Param: symbols");
        /*require(_params.wildSymbol == 255, "Invalid Param: wildSymbol");
        require(_params.scatterSymbol == 255, "Invalid Param: scatterSymbol");
        require(_params.bonusSymbol == 255, "Invalid Param: bonusSymbol");*/

        // Configurable
        require(_params.payoutConstant > 0, "Invalid Param: payoutConstant");
        require(_params.maxBetCredits > 0, "Invalid Param: maxBetCredits");
        require(_params.maxJackpotCredits > 0, "Invalid Param: maxJackpotCredits");
        require(_params.creditSizeWad > 0, "Invalid Param: creditSizeWad");
        _;
    }

    constructor(
        ERC20VaultPaymentProcessor.VaultParams memory vaultParams,
        ChainlinkConsumer.VRFParams memory vrfParams,
        address owner
    )
        ChainlinkConsumer(vrfParams)
        ERC20VaultPaymentProcessor(vaultParams)
        MultiLineSlots(getInitialParams(), getInitialWinlines(), owner)
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

    /*
        ERC4626 Hooks
    */
    function afterBurn(address owner, address receiver, uint256 shares) internal override {}
    function afterDeposit(address owner, uint256 assets, uint256 shares) internal override {}
}