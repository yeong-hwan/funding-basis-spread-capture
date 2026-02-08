// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IChainlinkAggregator
/// @notice Chainlink Price Feed interface
interface IChainlinkAggregator {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
}

/// @dev Arbitrum Chainlink Price Feeds
library ChainlinkFeeds {
    /// @dev ETH/USD Price Feed on Arbitrum
    address constant ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    /// @dev USDC/USD Price Feed on Arbitrum
    address constant USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
}
