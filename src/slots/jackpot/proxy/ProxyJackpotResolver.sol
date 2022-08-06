// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/slots/jackpot/JackpotResolver.sol";
import "src/slots/jackpot/proxy/ExternalJackpotResolver.sol";

abstract contract ProxyJackpotResolver is JackpotResolver {
    ExternalJackpotResolver internal proxyResolver;

    constructor (ExternalJackpotResolver _proxyResolver) {
        proxyResolver = _proxyResolver;
    }

    function addToJackpot(uint256 _jackpotWad, uint256 max) internal virtual override {
        proxyResolver.addToJackpotExternal(_jackpotWad);
    }

    function consumeJackpot() internal virtual override returns (uint256 out) {
        out = proxyResolver.consumeJackpotExternal();
    }

    function getJackpot() public view virtual override returns (uint256) {
        return proxyResolver.getJackpot();
    }
}