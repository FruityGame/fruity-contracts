// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { PaymentProcessor } from "src/payment/PaymentProcessor.sol";

abstract contract ERC20PaymentProcessor is PaymentProcessor {
    ERC20 public token;

    error AllowanceError(address account, uint256 allowance, uint256 wanted);
    error MsgValueNotAllowed();

    modifier userCanAfford(address user, uint256 betWad) {
        if (betWad == 0) revert InvalidDeposit(user, betWad);

        if (token.allowance(user, address(this)) < betWad) {
            revert AllowanceError(user, token.allowance(user, address(this)), betWad);
        }

        if (betWad > token.balanceOf(user)) {
            revert InsufficientFunds(user, token.balanceOf(user), betWad);
        }
        _;
    }

    constructor(ERC20 _token) {
        token = _token;
    }

    function _deposit(address from, uint256 paymentWad) internal override userCanAfford(from, paymentWad) {
        // Required because the bet methods exposed in the abstract slots contracts are payable.
        // This prevents the ERC20 Contracts accepting Eth (will result in user funds being stuck)
        if (msg.value > 0) revert MsgValueNotAllowed();
        token.transferFrom(from, address(this), paymentWad);
    }

    function _withdraw(address to, uint256 paymentWad) internal override canAfford(paymentWad) {
        token.transfer(to, paymentWad);
    }

    function _balance() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }
}