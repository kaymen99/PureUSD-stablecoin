// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library TokenHelper {
    function tokenDecimals(
        address token
    ) internal view returns (uint8 decimals) {
        decimals = IERC20Metadata(token).decimals();
    }

    function balanceOf(
        address token,
        address _account
    ) internal view returns (uint256) {
        return IERC20(token).balanceOf(_account);
    }

    function transferToken(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        bool success;
        if (from == address(this)) {
            success = IERC20(token).transfer(to, amount);
        } else {
            success = IERC20(token).transferFrom(from, to, amount);
        }
        require(success);
    }

    function transferNativeToken(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success);
    }
}
