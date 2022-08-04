// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 quantityWad) ERC20(
        "FRUITY",
        "FRTY",
        18
    ) {
        _mint(msg.sender, quantityWad);
    }

    function mintExternal(address to, uint256 amount) external {
        _mint(to, amount);
    }
}