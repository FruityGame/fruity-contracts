// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Owned } from "solmate/auth/Owned.sol";

import { EIP712 } from "src/mixins/EIP712.sol";
import { Certificates } from "src/libraries/crypto/Certificates.sol";

import { AbstractProxy } from "src/proxy/AbstractProxy.sol";
import { ProxyReceiver } from "src/proxy/ProxyReceiver.sol";
import { ERC20PaymentProcessor } from "src/payment/erc20/ERC20PaymentProcessor.sol";

contract ProxyRelayer is Owned, AbstractProxy {

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            CONSTANTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    bytes32 constant public END_SESSION_TYPEHASH = keccak256("EndSession(address user,address proxy,uint256 expiry,uint256 nonce)");

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            STORAGE
    /////////////////////////////////////////////////////////////////////////////////////////*/

    ERC20 public token;
    uint256 public fee;

    mapping(address => uint256) public sessionNonces;
    mapping(address => bool) public authorizedReceiver;

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            EVENTS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    event SessionStarted(address indexed user, address proxy, uint256 expiry);
    event SessionEnded(address indexed user, address proxy, uint256 expiry);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                            ERRORS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    error InvalidProxyReceiver(address receiver);
    error InvalidProxyAddress(address proxy);
    error InvalidExpiry(uint256 expiry);

    /*/////////////////////////////////////////////////////////////////////////////////////////
                                        PUBLIC METHODS
    /////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(address governance, ERC20 _token, uint256 _fee)
        EIP712(string(abi.encodePacked(address(this), "ProxyRelayer")), "1")
        Owned(governance)
    {
        token = _token;
        fee = _fee;
    }

    function startSession(address proxy, uint192 expiry, bytes32 r, bytes32 vs) public {
        if (proxy == address(0)) revert InvalidProxyAddress(proxy);
        if (expiry <= block.number) revert InvalidExpiry(expiry);

        // Validate the user's Session Certificate before cataloguing it
        _validateMessage(
            msg.sender,
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    msg.sender,
                    proxy,
                    expiry,
                    ++sessionNonces[msg.sender]
                )
            ),
            DOMAIN_SEPARATOR(),
            r, vs
        );

        emit SessionStarted(msg.sender, proxy, expiry);
    }

    function endSessionProxy(
        bytes32 rCert,
        bytes32 vsCert,
        uint256 certLhs,
        uint256 certRhs,
        bytes32 r,
        bytes32 vs
    ) public virtual {
        // Decompress/Unpack the certificate contents
        (address user, address proxy, uint256 expiry) = Certificates.expand(certLhs, certRhs);

        // (note): Expiry doesn't matter due to the nonce acting like a ratchet;
        // only the most recent Session Certificate is able to be cancelled/ended
        if (user == address(0) || proxy == address(0)) revert InvalidSession(user);

        // Validate the user's Session Certificate before cataloguing it
        _validateMessage(
            user,
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    user,
                    proxy,
                    expiry,
                    sessionNonces[user]
                )
            ),
            DOMAIN_SEPARATOR(),
            rCert, vsCert
        );

        // Validate the Proxy End Session request
        _validateMessage(
            proxy,
            keccak256(
                abi.encode(
                    END_SESSION_TYPEHASH,
                    user,
                    proxy,
                    expiry,
                    sessionNonces[user]++
                )
            ),
            DOMAIN_SEPARATOR(),
            r, vs
        );

        emit SessionEnded(user, proxy, expiry);
    }

    function endSession() public virtual {
        sessionNonces[msg.sender]++;
    }

    function relay(
        bytes32 rCert,
        bytes32 vsCert,
        uint256 certLhs,
        uint256 certRhs,
        bytes32 r,
        bytes32 vs,
        address target,
        bytes calldata _calldata
    ) public {
        // Ensures only trusted payment acceptors are forwarded to, to prevent
        // spamming of transactions to malicious contracts to siphon off relay fees
        if (!authorizedReceiver[target]) revert InvalidProxyReceiver(target);

        // Deposit the relayer fee into our account
        // TODO: SessionRegistry, evaluate the amount of gas left at this point,
        // appropriately adjust the fee according to price data (perhaps)
        token.transferFrom(address(uint160(certLhs & Certificates.ADDRESS_MASK)), address(this), fee);

        // Forward our request to the receiver. The receiver performs validation
        // of the certificate and the proxy signature (in case this contract is compromised)
        ProxyReceiver(target).executeProxy(rCert, vsCert, certLhs, certRhs, r, vs, _calldata);

        // Pay the fee to the relayer from our account post-execution
        token.transfer(msg.sender, fee);
    }

    function authorizeProxyReceiver(address proxy, bool authorized) public onlyOwner {
        authorizedReceiver[proxy] = authorized;
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }
}