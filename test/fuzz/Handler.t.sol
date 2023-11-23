// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import {PUSDController} from "../../src/PUSDController.sol";
import {PUSD} from "../../src/PUSD.sol";

contract Handler is Test {
    PUSDController controller;
    PUSD pUSD;

    ERC20DecimalsMock weth;
    ERC20DecimalsMock wbtc;

    uint256 constant MAX_DEPOSIT = type(uint128).max;
    address[] public depositors;

    constructor(PUSDController _controller, PUSD _pUSD) {
        controller = _controller;
        pUSD = _pUSD;
        address[] memory collateralArray = controller.getCollateralTokensList();
        weth = ERC20DecimalsMock(collateralArray[0]);
        wbtc = ERC20DecimalsMock(collateralArray[1]);
    }

    function deposit(uint256 collateralSeed, uint256 amount) public {
        address collateral = _getCollateralAddress(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT);
        vm.startPrank(msg.sender);
        ERC20DecimalsMock(collateral).mint(msg.sender, amount);
        ERC20DecimalsMock(collateral).approve(address(controller), amount);
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

    function mintPUSD(uint256 senderSeed, uint256 amount) public {
        uint256 length = depositors.length;
        if (length == 0) return;
        address sender = depositors[senderSeed % length];
        (uint256 totalPUSDMinted, uint256 totalCollateralInUSD) = controller
            .getUserData(sender);
        // Must not break health factor ==> 2 * totalCollateralInUSD > totalPUSDMinted
        int256 maxPUSDToMint = int256(
            (totalCollateralInUSD / 2) - totalPUSDMinted
        );
        if (maxPUSDToMint <= 0) return;
        amount = bound(amount, 1, uint256(maxPUSDToMint));
        vm.startPrank(sender);
        controller.mintPUSD(amount);
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
