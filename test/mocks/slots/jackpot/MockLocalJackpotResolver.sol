// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/jackpot/LocalJackpotResolver.sol";

contract MockLocalJackpotResolver is LocalJackpotResolver {
    function setJackpot(uint256 _jackpotWad) external {
        jackpotWad = _jackpotWad;
    }

    /*
        Mock methods to expose internal functionality
    */
    function addToJackpotExternal(uint256 _jackpotWad, uint256 max) external {
        addToJackpot(_jackpotWad, max);
    }

    function consumeJackpotExternal() external returns (uint256) {
        return consumeJackpot();
    }

    function getJackpotExternal() external view returns (uint256) {
        return getJackpot();
    }
}