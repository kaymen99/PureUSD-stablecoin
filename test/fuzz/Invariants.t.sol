// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20MockWithDecimals} from "../mocks/ERC20MockWithDecimals.sol";
import "../../script/DeployDSC.s.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCController controller;
    DSCToken dsc;
    HelperConfig config;
    Handler handler;

    ERC20MockWithDecimals weth;
    ERC20MockWithDecimals wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, controller, config) = deployer.run();
        (address wethAddress, address wbtcAddress, , , ) = config
            .activeConfig();
        weth = ERC20MockWithDecimals(wethAddress);
        wbtc = ERC20MockWithDecimals(wbtcAddress);
        handler = new Handler(controller, dsc);
        targetContract(address(handler));
    }

    function invariant_totalCollateralValueMustBeGreaterThanDSCSupply()
        public
        view
    {
        uint256 wethBalance = weth.balanceOf(address(controller));
        uint256 wbtcBalance = wbtc.balanceOf(address(controller));
        uint256 totalWethCollateralValue = controller.getUSDAmount(
            address(weth),
            wethBalance
        );
        uint256 totalWbtcCollateralValue = controller.getUSDAmount(
            address(wbtc),
            wbtcBalance
        );
        uint256 totalCollateralValue = totalWethCollateralValue +
            totalWbtcCollateralValue;
        uint256 totalDSCSupply = dsc.totalSupply();
        assert(totalCollateralValue >= totalDSCSupply);
    }
}
