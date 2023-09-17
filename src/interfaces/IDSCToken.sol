// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IDSCToken {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(uint256 amount) external;
}
