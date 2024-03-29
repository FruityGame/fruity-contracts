// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Auth } from "solmate/auth/Auth.sol";
import { JackpotResolver } from "src/games/slots/jackpot/JackpotResolver.sol";

abstract contract ExternalJackpotResolver is JackpotResolver, Auth {
    uint256 max;

    constructor(uint256 _max) {
        max = _max;
    }

    function addToJackpotExternal(uint256 _jackpotWad) external virtual requiresAuth() {
        addToJackpot(_jackpotWad, max);
    }

    function consumeJackpotExternal() external virtual requiresAuth() returns (uint256) {
        return consumeJackpot();
    }
}