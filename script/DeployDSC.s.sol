// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCController} from "../src/DSCController.sol";
import {DSCToken} from "../src/DSCToken.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public owner = address(1);
    address public feeRecipient = address(2);

    function run() external returns (DSCToken, DSCController, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (
            address weth,
            address wbtc,
            address wethUSDPriceFeed,
            address wbtcUSDPriceFeed,
            uint256 deployerKey
        ) = config.activeConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];

        vm.startBroadcast(deployerKey);

        DSCToken dscToken = new DSCToken();
        DSCController controller = new DSCController(
            address(dscToken),
            owner,
            feeRecipient,
            tokenAddresses,
            priceFeedAddresses
        );
        dscToken.transferOwnership(address(controller));

        vm.stopBroadcast();

        return (dscToken, controller, config);
    }
}
