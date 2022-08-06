// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/proxy/ExternalPaymentProcessor.sol";

abstract contract ProxyPaymentProcessor is PaymentProcessor {
    ExternalPaymentProcessor proxyProcessor;

    constructor (ExternalPaymentProcessor _proxyProcessor) {
        proxyProcessor = _proxyProcessor;
    }

    function _deposit(address from, uint256 paymentWad) internal virtual override {
        proxyProcessor.depositExternal(from, paymentWad);
    }

    function _withdraw(address to, uint256 paymentWad) internal virtual override {
        proxyProcessor.withdrawExternal(to, paymentWad);
    }

    function _balance() internal view virtual override returns (uint256) {
        return proxyProcessor.balanceExternal();
    }
}