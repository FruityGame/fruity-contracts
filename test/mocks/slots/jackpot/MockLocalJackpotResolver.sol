// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/jackpot/LocalJackpotResolver.sol";

abstract contract MockLocalJackpotResolver is LocalJackpotResolver {
    function setJackpot(uint256 _jackpotWad) external {
        jackpotWad = _jackpotWad;
    }
}