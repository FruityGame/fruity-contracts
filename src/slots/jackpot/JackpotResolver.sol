// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

abstract contract JackpotResolver {
    function addToJackpot(uint256 _jackpotWad, uint256 max) internal virtual;
    function consumeJackpot() internal virtual returns (uint256 out);
    function getJackpot() internal view virtual returns (uint256);
}