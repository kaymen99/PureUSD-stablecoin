// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Pure USD stablecoin
/// @author kaymen99
/// @notice This is ERC20 is an implementation of algorithmic stablecoin, users can deposit collaterals (WETH/WBTC) into controller and mint the PUSD token
/// @dev The PUSDController is the owner of this contract and is the only address that can mint/burn PUSD tokens
contract PUSD is ERC20Burnable, Ownable {
    // ************ //
    //    Errors    //
    // ************ //

    error InvalidMint();
    error InvalidBurnAmount();
    error AmountExceedsBalance();

    constructor() ERC20("Pure USD", "PUSD") Ownable(msg.sender) {}

    // ***************** //
    //  Public/external  //
    // ***************** //

    /// @notice Allow controller to mint PUSD tokens to users
    /// @dev Only callable by controller
    /// @param to address to mint tokens to
    /// @param amount amount of PUSD tokens to mint
    /// @return boolean value: true if mint success, otherwise false
    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0) || amount == 0) revert InvalidMint();
        _mint(to, amount);
        return true;
    }

    /// @notice Allow controller to burn PUSD tokens returned by users
    /// @dev Only callable by controller
    /// @param amount amount of PUSD tokens to burn
    function burn(uint256 amount) public override onlyOwner {
        if (amount == 0) revert InvalidBurnAmount();
        if (balanceOf(msg.sender) < amount) revert AmountExceedsBalance();
        super.burn(amount);
    }

    /// @notice Allow controller to burn PUSD tokens from specific address
    /// @dev used during flashMint operation, only callable by controller
    /// @param account address to burn PUSD from
    /// @param amount amount of PUSD tokens to burn
    function burnFrom(
        address account,
        uint256 amount
    ) public override onlyOwner {
        if (amount == 0) revert InvalidBurnAmount();
        if (balanceOf(account) < amount) revert AmountExceedsBalance();
        _burn(account, amount);
    }
}
