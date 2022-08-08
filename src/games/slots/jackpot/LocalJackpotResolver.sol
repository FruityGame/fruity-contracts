// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { JackpotResolver } from "src/games/slots/jackpot/JackpotResolver.sol";

abstract contract LocalJackpotResolver is JackpotResolver {
    uint256 public jackpotWad;

    function addToJackpot(uint256 _jackpotWad, uint256 max) internal virtual override {
        uint256 wanted = jackpotWad + _jackpotWad;

        if (wanted > max) {
            emit JackpotChanged(jackpotWad, max);
            jackpotWad = max;
        } else {
            emit JackpotChanged(jackpotWad, wanted);
            jackpotWad = wanted;
        }
    }

    function consumeJackpot() internal virtual override returns (uint256 out) {
        out = jackpotWad;
        jackpotWad = 0;

        emit JackpotChanged(out, jackpotWad);
    }

    function getJackpot() public view virtual override returns (uint256) {
        return jackpotWad;
    }
}