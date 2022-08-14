// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";

import { ERC20Snapshot } from "src/tokens/ERC20Snapshot.sol";
import { ExternalPaymentProcessor } from "src/payment/proxy/ExternalPaymentProcessor.sol";
import { ERC20VaultPaymentProcessor } from "src/payment/vault/ERC20VaultPaymentProcessor.sol";

contract GamesPool is ERC20Snapshot, ERC20VaultPaymentProcessor, ExternalPaymentProcessor, RolesAuthority {
    enum Roles {
        Game,
        Governor
    }

    modifier canAfford(uint256 amount) override {_;}

    event GameAdded(address indexed game);
    event GameRemoved(address indexed game);

    constructor(
        address governorContract,
        ERC20VaultPaymentProcessor.VaultParams memory vaultParams
    )
        ERC20VaultPaymentProcessor(vaultParams)
        RolesAuthority(address(this), this)
    {
        // Setup roles
        // (note): Calling setRoleCapability was reverting due to 0 code, I can't tell what that means. Solmate so based.
        getRolesWithCapability[address(this)][ExternalPaymentProcessor.withdrawExternal.selector] |= bytes32(1 << uint8(Roles.Game));
        getRolesWithCapability[address(this)][ExternalPaymentProcessor.depositExternal.selector] |= bytes32(1 << uint8(Roles.Game));

        getRolesWithCapability[address(this)][GamesPool.addGame.selector] |= bytes32(1 << uint8(Roles.Governor));
        getRolesWithCapability[address(this)][GamesPool.removeGame.selector] |= bytes32(1 << uint8(Roles.Governor));

        setUserRole(governorContract, uint8(Roles.Governor), true);
    }

    function addGame(address game) external requiresAuth() {
        setUserRole(game, uint8(Roles.Game), true);
        emit GameAdded(game);
    }

    function removeGame(address game) external requiresAuth() {
        setUserRole(game, uint8(Roles.Game), false);
        emit GameRemoved(game);
    }
}