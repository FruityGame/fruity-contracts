// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";
import { ExternalPaymentProcessor } from "src/payment/proxy/ExternalPaymentProcessor.sol";

abstract contract ProxyPaymentProcessor is PaymentProcessor {
    ExternalPaymentProcessor internal proxyProcessor;

    constructor (ExternalPaymentProcessor _proxyProcessor) {
        proxyProcessor = _proxyProcessor;
    }

    function _deposit(address from, uint256 paymentWad) internal virtual override {
        proxyProcessor.depositExternal(from, paymentWad);
    }

    function _withdraw(address to, uint256 paymentWad) internal virtual override {
        proxyProcessor.withdrawExternal(to, paymentWad);
    }

    function _balance() public view virtual override returns (uint256) {
        return proxyProcessor._balance();
    }
}