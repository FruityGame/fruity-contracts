// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

abstract contract JackpotResolver {
    event JackpotChanged(uint256 oldValue, uint256 newValue);

    function addToJackpot(uint256 _jackpotWad, uint256 max) internal virtual;
    function consumeJackpot() internal virtual returns (uint256 out);
    function getJackpot() public view virtual returns (uint256);
}