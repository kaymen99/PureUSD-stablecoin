// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {PUSDController} from "../src/PUSDController.sol";
import {PUSD} from "../src/PUSD.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPUSD is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public owner = address(1);
    address public feeRecipient = address(2);

    function run() external returns (PUSD, PUSDController, HelperConfig) {
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

        PUSD pUSD = new PUSD();
        PUSDController controller = new PUSDController(
            address(pUSD),
            owner,
            feeRecipient,
            tokenAddresses,
            priceFeedAddresses
        );
        pUSD.transferOwnership(address(controller));

        vm.stopBroadcast();

        return (pUSD, controller, config);
    }
}
