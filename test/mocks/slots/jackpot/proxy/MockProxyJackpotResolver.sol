// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/jackpot/proxy/ProxyJackpotResolver.sol";

contract MockProxyJackpotResolver is ProxyJackpotResolver {
    constructor (ExternalJackpotResolver proxyResolver) ProxyJackpotResolver(proxyResolver) {}

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