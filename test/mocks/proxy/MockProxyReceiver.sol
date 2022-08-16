// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ProxyReceiver } from "src/proxy/ProxyReceiver.sol";
import { SessionRegistry } from "src/proxy/SessionRegistry.sol";
import { ERC20PaymentProcessor } from "src/payment/erc20/ERC20PaymentProcessor.sol";

contract MockProxyReceiver is ERC20PaymentProcessor, ProxyReceiver {
    uint256 public executedCount;

    constructor(ERC20 token, SessionRegistry sessionRegistry)
        ERC20PaymentProcessor(token)
        ProxyReceiver(sessionRegistry)
    {

    }

    function mockExecute() public {
        executedCount++;
    }
}