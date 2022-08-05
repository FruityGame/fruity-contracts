// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/jackpot/JackpotResolver.sol";

abstract contract PooledJackpotResolver is JackpotResolver {
    uint256 public jackpotWad;

    function addToJackpot(uint256 _jackpotWad) internal virtual override {
        jackpotWad += _jackpotWad;        
    }

    function consumeJackpot() internal virtual override returns (uint256 out) {
        out = jackpotWad;
        jackpotWad = 0;
    }

    function getJackpot() internal view virtual override returns (uint256) {
        return jackpotWad;
    }
}