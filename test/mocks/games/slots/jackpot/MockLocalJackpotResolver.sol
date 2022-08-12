// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/games/slots/jackpot/LocalJackpotResolver.sol";

contract MockLocalJackpotResolver is LocalJackpotResolver {
    function setJackpot(uint256 _jackpotWad) external {
        jackpotWad = _jackpotWad;
    }

    /*
        Mock methods to expose internal functionality
    */
    function _addToJackpotExternal(uint256 _jackpotWad, uint256 max) external {
        addToJackpot(_jackpotWad, max);
    }

    function _consumeJackpotExternal() external returns (uint256) {
        return consumeJackpot();
    }
}