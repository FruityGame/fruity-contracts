// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "test/mocks/payment/MockNativeVaultPaymentProcessor.sol";

contract WithdrawReentrancy {
    bool ran = false;
    receive() external payable {
        if (!ran) {
            ran = true;
            MockNativeVaultPaymentProcessor(msg.sender).deposit{value: msg.value}(msg.value, address(this));
            MockNativeVaultPaymentProcessor(msg.sender).withdraw(1e18, address(this), address(this));
            MockNativeVaultPaymentProcessor(msg.sender).withdraw(1e18, address(this), address(this));
        }
    }

    fallback() external payable {
        if (!ran) {
            ran = true;
            MockNativeVaultPaymentProcessor(msg.sender).deposit{value: msg.value}(msg.value, address(this));
            MockNativeVaultPaymentProcessor(msg.sender).withdraw(1e18, address(this), address(this));
            MockNativeVaultPaymentProcessor(msg.sender).withdraw(1e18, address(this), address(this));
        }
    }
}

contract RedeemReentrancy  {
    bool ran = false;
    receive() external payable {
        if (!ran) {
            ran = true;
            MockNativeVaultPaymentProcessor(msg.sender).mint{value: msg.value}(msg.value, address(this));
            MockNativeVaultPaymentProcessor(msg.sender).redeem(1e18, address(this), address(this));
            MockNativeVaultPaymentProcessor(msg.sender).redeem(1e18, address(this), address(this));
        }
    }

    fallback() external payable {
        if (!ran) {
            ran = true;
            MockNativeVaultPaymentProcessor(msg.sender).mint{value: msg.value}(msg.value, address(this));
            MockNativeVaultPaymentProcessor(msg.sender).redeem(1e18, address(this), address(this));
            MockNativeVaultPaymentProcessor(msg.sender).redeem(1e18, address(this), address(this));
        }
    }
}