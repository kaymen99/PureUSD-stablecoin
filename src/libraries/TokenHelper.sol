// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library TokenHelper {
    function tokenDecimals(
        address token
    ) internal view returns (uint8 decimals) {
        decimals = IERC20Metadata(token).decimals();
    }

    function transferToken(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_amount == 0) {
            return;
        }
        if (_token == address(0)) {
            transferNativeToken(_to, _amount);
        } else {
            transferERC20(_token, _from, _to, _amount);
        }
    }

    function transferERC20(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == address(this)) {
            IERC20(_token).transfer(_to, _amount);
        } else {
            IERC20(_token).transferFrom(_from, _to, _amount);
        }
    }

    function transferNativeToken(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success);
    }
}
