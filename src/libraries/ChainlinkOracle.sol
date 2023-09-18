// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library ChainlinkOracle {
    error InvalidPrice();

    // duration after which returned price is considered outdated
    uint256 private constant TIMEOUT = 2 hours;

    /// @notice Fetch token price using chainlink price feeds
    /// @dev Checks that returned price is positive and not stale
    /// @param priceFeed chainlink aggregator interface
    /// @return price of the token
    function getPrice(
        AggregatorV3Interface priceFeed
    ) public view returns (uint256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        if (
            answer <= 0 ||
            updatedAt == 0 ||
            answeredInRound < roundId ||
            block.timestamp - updatedAt > TIMEOUT
        ) revert InvalidPrice();

        price = uint256(answer);
    }

    /// @notice Get timeout duration after which prices are considered stale
    function getTimeout(AggregatorV3Interface) public pure returns (uint256) {
        return TIMEOUT;
    }
}
