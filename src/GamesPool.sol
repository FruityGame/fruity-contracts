// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Governance } from "src/governance/Governance.sol";
import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";
import { ExternalPaymentProcessor } from "src/payment/proxy/ExternalPaymentProcessor.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";

contract GamesPool is Governance, ERC20VaultPaymentProcessor, ExternalPaymentProcessor, RolesAuthority {
    uint8 constant AUTHORIZED_GAME = 1;

    modifier canAfford(uint256 amount) override {_;}

    event GameAdded(address indexed game);
    event GameRemoved(address indexed game);

    constructor(
        uint256 minProposalDeposit,
        Governance.Params memory governanceParams,
        ERC20VaultPaymentProcessor.VaultParams memory vaultParams
    )
        Governance(minProposalDeposit, governanceParams)
        ERC20VaultPaymentProcessor(vaultParams)
        RolesAuthority(msg.sender, this)
    {
        // Setup roles
        //setRoleCapability(AUTHORIZED_GAME, address(this), GamesPool.depositExternal.selector, true);
        setRoleCapability(AUTHORIZED_GAME, address(this), ExternalPaymentProcessor.withdrawExternal.selector, true);
    }

    function addGame(address game) external onlyGovernance() {
        setUserRole(game, AUTHORIZED_GAME, true);
        emit GameAdded(game);
    }

    function removeGame(address game) external onlyGovernance() {
        setUserRole(game, AUTHORIZED_GAME, false);
        emit GameRemoved(game);
    }
}