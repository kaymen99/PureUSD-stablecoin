// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFlashloanReceiver} from "../../src/interfaces/IFlashloanReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Extension to Openzeppelin ERC20Mock contract
/// @author kaymen99
/// @notice Allows to specify the decimal number of mock token
contract FlashloanReceiverMock is IFlashloanReceiver {
    constructor(
        address pUSDController,
        address pUSD,
        address weth,
        address wbtc
    ) {
        IERC20(pUSD).approve(address(pUSDController), type(uint256).max);
        IERC20(weth).approve(address(pUSDController), type(uint256).max);
        IERC20(wbtc).approve(address(pUSDController), type(uint256).max);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bool) {
        // do user operations

        return true;
    }
}

contract BadFlashloanReceiverMock is IFlashloanReceiver {
    constructor(
        address pUSDController,
        address pUSD,
        address weth,
        address wbtc
    ) {
        IERC20(pUSD).approve(address(pUSDController), type(uint256).max);
        IERC20(weth).approve(address(pUSDController), type(uint256).max);
        IERC20(wbtc).approve(address(pUSDController), type(uint256).max);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bool) {
        // do user operations

        // will always return false which should revert the flashloan tx
        return false;
    }
}
