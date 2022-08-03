// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "src/payment/PaymentProcessor.sol";

abstract contract ERC20PaymentProcessor is PaymentProcessor {
    ERC20 public token;

    error AllowanceError(address account, uint256 allowance, uint256 wanted);

    modifier isZeroMsgValue() {
        require(msg.value == 0, "Contract doesn't accept the native token");
        _;
    }

    modifier userCanAfford(address user, uint256 betWad) {
        if (token.allowance(user, address(this)) < betWad) {
            revert AllowanceError(user, token.allowance(user, address(this)), betWad);
        }

        if (betWad > token.balanceOf(user)) {
            revert InsufficientFunds(user, token.balanceOf(user), betWad);
        }
        _;
    }

    constructor(address _token) {
        token = ERC20(_token);
    }

    function _deposit(address from, uint256 paymentWad) internal override isZeroMsgValue() userCanAfford(from, paymentWad) {
        token.transferFrom(from, address(this), paymentWad);
    }

    function _withdraw(address to, uint256 paymentWad) internal override canAfford(paymentWad) {
        token.transfer(to, paymentWad);
    }

    function _balance() internal view override returns (uint256) {
        return token.balanceOf(address(this));
    }
}