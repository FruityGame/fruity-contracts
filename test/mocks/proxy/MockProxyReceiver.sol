// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ProxyReceiver } from "src/proxy/ProxyReceiver.sol";
import { ProxyRelayer } from "src/proxy/ProxyRelayer.sol";

contract MockProxyReceiver is ProxyReceiver {
    uint256 public amount;

    constructor() {}

    function mockExecute(uint256 _amount) public {
        amount = _amount;
    }

    function mockExecuteRevert() public {
        revert();
    }
}