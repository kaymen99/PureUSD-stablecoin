// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import "../../script/DeployPUSD.s.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployPUSD deployer;
    PUSDController controller;
    PUSD pUSD;
    HelperConfig config;
    Handler handler;

    ERC20DecimalsMock weth;
    ERC20DecimalsMock wbtc;

    function setUp() public {
        deployer = new DeployPUSD();
        (pUSD, controller, config) = deployer.run();
        (address wethAddress, address wbtcAddress, , , ) = config
            .activeConfig();
        weth = ERC20DecimalsMock(wethAddress);
        wbtc = ERC20DecimalsMock(wbtcAddress);
        handler = new Handler(controller, pUSD);
        targetContract(address(handler));
    }

    function invariant_totalCollateralValueMustBeGreaterThanPUSDSupply()
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
        uint256 totalPUSDSupply = pUSD.totalSupply();
        assert(totalCollateralValue >= totalPUSDSupply);
    }
}
