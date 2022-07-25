// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";

contract MockFruityERC20 is ERC20 {
    constructor() ERC20(
        "FRUITY",
        "FRTY",
        8
    ) {
        _mint(msg.sender, 10000000);
    }
}