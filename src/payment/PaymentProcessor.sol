// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

abstract contract PaymentProcessor {
    error InsufficientFunds(address account, uint256 balance, uint256 wanted);
    error InvalidDeposit(address account, uint256 deposit);

    modifier canAfford(uint256 payoutWad) virtual;

    function _deposit(address from, uint256 paymentWad) internal virtual;
    function _withdraw(address to, uint256 paymentWad) internal virtual;
    function _balance() public view virtual returns (uint256);
}