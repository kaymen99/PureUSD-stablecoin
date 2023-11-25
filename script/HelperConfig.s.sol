// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20DecimalsMock} from "../test/mocks/ERC20DecimalsMock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint8 public constant ETH_DECIMALS = 18;
    uint8 public constant BTC_DECIMALS = 8;

    // USD Chainlink oracle are given in 8 decimals
    uint8 public constant PRICE_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8; // 1 ETH = 2000$
    int256 public constant BTC_USD_PRICE = 30000e8; // 1 BTC = 30000$

    struct Config {
        address weth;
        address wbtc;
        address wethUSDPriceFeed;
        address wbtcUSDPriceFeed;
        uint256 deployerKey;
    }

    Config public activeConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else {
            activeConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (Config memory config) {
        config = Config({
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wethUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (Config memory) {
        if (activeConfig.weth != address(0)) return activeConfig;

        vm.startBroadcast();

        ERC20DecimalsMock wethMock = new ERC20DecimalsMock(ETH_DECIMALS);
        ERC20DecimalsMock wbtcMock = new ERC20DecimalsMock(BTC_DECIMALS);

        MockV3Aggregator ethUSDFeed = new MockV3Aggregator(
            PRICE_DECIMALS,
            ETH_USD_PRICE
        );
        MockV3Aggregator btcUSDFeed = new MockV3Aggregator(
            PRICE_DECIMALS,
            BTC_USD_PRICE
        );

        vm.stopBroadcast();

        return
            Config({
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                wethUSDPriceFeed: address(ethUSDFeed),
                wbtcUSDPriceFeed: address(btcUSDFeed),
                deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
            });
    }
}
