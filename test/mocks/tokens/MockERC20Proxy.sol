// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20Hooks } from "src/tokens/ERC20Hooks.sol";
import { ERC20Proxy } from "src/tokens/ERC20Proxy.sol";

contract MockERC20Proxy is ERC20Proxy {
    constructor(uint256 quantityWad) ERC20Hooks("FRUITY", "FRTY", 18) {
        _mint(msg.sender, quantityWad);
    }

    function mintExternal(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burnExternal(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function _afterMint(address to, uint256 newBalance, uint256 newTotalSupply) internal virtual override {}

    function _afterBurn(address from, uint256 newBalance, uint256 newTotalSupply) internal virtual override {}

    function _afterTransfer(address from, address to, uint256 fromNewBalance, uint256 toNewBalance) internal virtual override {}

    function getSession(address user) external view returns (Session memory) {
        return sessions[user];
    }

    function incrementNonce(address proxy) external {
        ++nonces[proxy];
    }
}