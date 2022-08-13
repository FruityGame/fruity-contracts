// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { Math } from "src/libraries/Math.sol";
import { Governance } from "src/governance/Governance.sol";
import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";
import { AbstractERC4626 } from "src/mixins/AbstractERC4626.sol";
import { ExternalPaymentProcessor } from "src/payment/proxy/ExternalPaymentProcessor.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";

contract GamesPool is Governance, ERC20VaultPaymentProcessor, ExternalPaymentProcessor, RolesAuthority {
    uint8 constant AUTHORIZED_GAME = 1;

    modifier canAfford(uint256 amount) override {_;}

    event GameAdded(address indexed game);
    event GameRemoved(address indexed game);

    uint256 internal pastBalance;

    constructor(
        Governance.ExternalParams memory governanceParams,
        ERC20VaultPaymentProcessor.VaultParams memory vaultParams
    )
        Governance(governanceParams)
        ERC20VaultPaymentProcessor(vaultParams)
        RolesAuthority(address(this), this)
    {
        // Setup roles
        // (note): Calling setRoleCapability was reverting due to 0 code, I can't tell what that means
        getRolesWithCapability[address(this)][ExternalPaymentProcessor.withdrawExternal.selector] |= bytes32(1 << AUTHORIZED_GAME);
        getRolesWithCapability[address(this)][ExternalPaymentProcessor.depositExternal.selector] |= bytes32(1 << AUTHORIZED_GAME);
        //setRoleCapability(AUTHORIZED_GAME, address(this), ExternalPaymentProcessor.withdrawExternal.selector, true);
    }

    function addGame(address game) external onlyGovernance() {
        setUserRole(game, AUTHORIZED_GAME, true);
        emit GameAdded(game);
    }

    function removeGame(address game) external onlyGovernance() {
        setUserRole(game, AUTHORIZED_GAME, false);
        emit GameRemoved(game);
    }

    /*
        ERC4626 Hook Overrides
    */

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual override(ERC20VaultPaymentProcessor, AbstractERC4626) {
        ERC20VaultPaymentProcessor.beforeWithdraw(assets, shares);
    }
}