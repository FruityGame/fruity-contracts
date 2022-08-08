// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 < 0.9.0;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Governance } from "src/governance/Governance.sol";
import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";
import { ExternalPaymentProcessor } from "src/payment/proxy/ExternalPaymentProcessor.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";

contract GamesPool is Governance, ERC20VaultPaymentProcessor, ExternalPaymentProcessor, RolesAuthority {
    modifier canAfford(uint256 amount) override {_;}

    constructor(
        uint256 minProposalDeposit,
        Governance.Params memory governanceParams,
        ERC20 asset, string memory name, string memory symbol
    )
        Governance(minProposalDeposit, governanceParams)
        ERC20VaultPaymentProcessor(asset, name, symbol)
        RolesAuthority(msg.sender, this)
    {}
}