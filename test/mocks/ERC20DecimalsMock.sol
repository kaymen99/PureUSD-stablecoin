// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title Extension to Openzeppelin ERC20Mock contract
/// @author kaymen99
/// @notice Allows to specify the decimal number of mock token
/// @dev For exmaple for mocking ETH we put 18 and for WBTC there are 8, this will allow more realistic testing
contract ERC20DecimalsMock is ERC20Mock {
    uint8 public tokenDecimals;

    constructor(uint8 _decimals) ERC20Mock() {
        tokenDecimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
}
