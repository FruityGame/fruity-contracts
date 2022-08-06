// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "src/payment/proxy/ExternalPaymentProcessor.sol";
import "src/payment/proxy/ProxyPaymentProcessor.sol";

contract MockProxyPaymentProcessor is ProxyPaymentProcessor {
    modifier canAfford(uint256 payoutWad) override {
        _;
    }

    constructor(ExternalPaymentProcessor externalPaymentProcessor) ProxyPaymentProcessor(externalPaymentProcessor) {}

    function _depositExternal(address from, uint256 paymentWad) external payable {
        _deposit(from, paymentWad);
    }

    function _withdrawExternal(address to, uint256 paymentWad) external {
        _withdraw(to, paymentWad);
    }

    function _balanceExternal() external view returns (uint256) {
        return _balance();
    }
}