import { ERC20 } from "solmate/tokens/ERC20.sol";

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20Hooks is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _afterTransfer(msg.sender, to, balanceOf[msg.sender] -= amount, balanceOf[to] += amount);

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _afterTransfer(from, to, balanceOf[from] -= amount, balanceOf[to] += amount);

        emit Transfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual override {
        _afterMint(to, balanceOf[to] += amount, totalSupply += amount);

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual override {
        _afterBurn(from, balanceOf[from] -= amount, totalSupply -= amount);

        emit Transfer(from, address(0), amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _afterMint(address to, uint256 newBalance, uint256 newTotalSupply) internal virtual;

    function _afterBurn(address from, uint256 newBalance, uint256 newTotalSupply) internal virtual;

    function _afterTransfer(address from, address to, uint256 fromNewBalance, uint256 toNewBalance) internal virtual;
}
