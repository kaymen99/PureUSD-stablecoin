// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ChainlinkOracle} from "../../src/libraries/ChainlinkOracle.sol";

contract ChainlinkOracleTest is StdCheats, Test {
    using ChainlinkOracle for AggregatorV3Interface;

    MockV3Aggregator public aggregator;

    function setUp() public {
        aggregator = new MockV3Aggregator(8, 1000 ether);
    }

    function testGetTimeOut() public {
        uint256 timeOut = AggregatorV3Interface(address(aggregator))
            .getTimeout();
        assertEq(timeOut, 2 hours);
    }

    function testRevertIfStalePrice() public {
        vm.warp(block.timestamp + 3 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(ChainlinkOracle.InvalidPrice.selector);
        AggregatorV3Interface(address(aggregator)).getPrice();
    }

    function testRevertIfPriceIsZeroOrNegative() public {
        // Set zero price in mock
        aggregator.updateAnswer(0);
        vm.expectRevert(ChainlinkOracle.InvalidPrice.selector);
        AggregatorV3Interface(address(aggregator)).getPrice();

        // Set negative price in mock
        aggregator.updateAnswer(-100e8);
        vm.expectRevert(ChainlinkOracle.InvalidPrice.selector);
        AggregatorV3Interface(address(aggregator)).getPrice();
    }

    function testRevertOnBadAnswer() public {
        uint80 _roundId = 0;
        int256 _answer = 1000e8;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(ChainlinkOracle.InvalidPrice.selector);
        AggregatorV3Interface(address(aggregator)).getPrice();
    }
}
