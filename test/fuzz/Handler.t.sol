// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20MockWithDecimals} from "../mocks/ERC20MockWithDecimals.sol";
import {DSCController} from "../../src/DSCController.sol";
import {DSCToken} from "../../src/DSCToken.sol";

contract Handler is Test {
    DSCController controller;
    DSCToken dsc;

    ERC20MockWithDecimals weth;
    ERC20MockWithDecimals wbtc;

    uint256 constant MAX_DEPOSIT = type(uint128).max;
    address[] public depositors;

    constructor(DSCController _controller, DSCToken _dsc) {
        controller = _controller;
        dsc = _dsc;
        address[] memory collateralArray = controller.getCollateralTokensList();
        weth = ERC20MockWithDecimals(collateralArray[0]);
        wbtc = ERC20MockWithDecimals(collateralArray[1]);
    }

    function deposit(uint256 collateralSeed, uint256 amount) public {
        address collateral = _getCollateralAddress(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT);
        vm.startPrank(msg.sender);
        ERC20MockWithDecimals(collateral).mint(msg.sender, amount);
        ERC20MockWithDecimals(collateral).approve(address(controller), amount);
        controller.deposit(collateral, msg.sender, amount);
        vm.stopPrank();
        depositors.push(msg.sender);
    }

    function withdraw(uint256 collateralSeed, uint256 amount) public {
        address collateral = _getCollateralAddress(collateralSeed);
        uint256 maxCollateralAmount = controller.getUserCollateralAmount(
            msg.sender,
            collateral
        );
        amount = bound(amount, 0, maxCollateralAmount);
        if (amount == 0) return;
        controller.withdraw(collateral, amount);
    }

    function minDSC(uint256 senderSeed, uint256 amount) public {
        uint256 length = depositors.length;
        if (length == 0) return;
        address sender = depositors[senderSeed % length];
        (uint256 totalDSCMinted, uint256 totalCollateralInUSD) = controller
            .getUserData(sender);
        // Must not break health factor ==> 2 * totalCollateralInUSD > totalDSCMinted
        int256 maxDSCToMint = int256(
            (totalCollateralInUSD / 2) - totalDSCMinted
        );
        if (maxDSCToMint <= 0) return;
        amount = bound(amount, 1, uint256(maxDSCToMint));
        vm.startPrank(sender);
        controller.mintDSC(amount);
        vm.stopPrank();
    }

    function _getCollateralAddress(
        uint256 collateralSeed
    ) internal view returns (address) {
        if (collateralSeed % 2 == 0) {
            return address(weth);
        }
        return address(wbtc);
    }
}
