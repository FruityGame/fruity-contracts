// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/jackpot/JackpotResolver.sol";

abstract contract LocalJackpotResolver is JackpotResolver {
    uint256 public jackpotWad;

    function addToJackpot(uint256 _jackpotWad, uint256 max) internal virtual override {
        if (jackpotWad + _jackpotWad > max) {
            _jackpotWad = max - jackpotWad;
        }

        emit JackpotChanged(jackpotWad, jackpotWad + _jackpotWad);

        jackpotWad += _jackpotWad;

    }

    function consumeJackpot() internal virtual override returns (uint256 out) {
        out = jackpotWad;
        jackpotWad = 0;

        emit JackpotChanged(out, jackpotWad);
    }

    function getJackpot() internal view virtual override returns (uint256) {
        return jackpotWad;
    }
}