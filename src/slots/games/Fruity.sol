// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/NativeTokenSlots.sol";
import "src/randomness/consumer/Chainlink.sol";

// Flag used to denote an active or fulfilled session
uint256 constant ACTIVE_SESSION = 1 << 255;
// Mask to exclude the above bit in winlineCount
uint256 constant WINLINE_COUNT_MASK = (1 << 254) - 1;

// Amazing language, truly
/*uint256[15] constant FRUITY_WINLINES = [
    341, 682, 1023, 630, 871,
    986, 671, 473, 413, 854,
    599, 873, 637, 869, 629,
    474, 415, 985, 669, 874
];*/

contract Fruity is NativeTokenSlots, ChainlinkConsumer {
    mapping(uint256 => SlotSession) private sessions;

    constructor(
        SlotParams memory slotParams,
        VaultParams memory vaultParams,
        VRFParams memory vrfParams
    )
        ChainlinkConsumer(vrfParams)
        NativeTokenSlots(
            slotParams,
            vaultParams,
            getInitialWinlines()
        )
    {}

    function getSession(uint256 betId) internal view override
    returns (SlotSession memory session) {
        session = sessions[betId];

        if (session.winlineCount & ACTIVE_SESSION != ACTIVE_SESSION) {
            revert InvalidSession(session.user, betId);
        }

        // Omit the session lock bit from the returned winline count
        session.winlineCount &= WINLINE_COUNT_MASK;
    }

    function startSession(uint256 betId, SlotSession memory session) internal override {
        if (session.winlineCount & ACTIVE_SESSION == ACTIVE_SESSION) {
            revert InvalidSession(session.user, betId);
        }

        session.winlineCount |= ACTIVE_SESSION;
        sessions[betId] = session;
    }

    function endSession(uint256 betId) internal override {
        if (sessions[betId].winlineCount & ACTIVE_SESSION != ACTIVE_SESSION) {
            revert InvalidSession(sessions[betId].user, betId);
        }

        sessions[betId].winlineCount ^= ACTIVE_SESSION;
    }

    // I hate this language so much
    function getInitialWinlines() private pure returns (uint256[] memory out) {
        out[0] = 341; out[1] = 682; out[2] = 1023; out[3] = 630; out[4] = 871;
        out[5] = 986; out[6] = 671; out[7] = 473; out[8] = 413; out[9] = 854;
        out[1] = 599; out[11] = 873; out[12] = 637; out[13] = 869; out[14] = 629;
        out[15] = 474; out[16] = 415; out[17] = 985; out[18] = 669; out[19] = 874;
    }
}