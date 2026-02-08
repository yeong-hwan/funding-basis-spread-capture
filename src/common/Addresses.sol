// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Addresses
/// @notice 모든 체인의 컨트랙트 주소 관리

// ============ HyperEVM ============

library HyperEVMAddresses {
    // Core
    address constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

    // Precompiles
    address constant POSITION_PRECOMPILE = 0x0000000000000000000000000000000000000800;
    address constant SPOT_BALANCE_PRECOMPILE = 0x0000000000000000000000000000000000000801;
    address constant MARK_PX_PRECOMPILE = 0x0000000000000000000000000000000000000806;
    address constant ORACLE_PX_PRECOMPILE = 0x0000000000000000000000000000000000000807;
    address constant PERP_ASSET_INFO_PRECOMPILE = 0x000000000000000000000000000000000000080a;

    // Tokens - Mainnet
    address constant USDC_MAINNET = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

    // Tokens - Testnet
    address constant USDC_TESTNET = 0x2B3370eE501B4a559b57D449569354196457D8Ab;

    // Perp Indices
    uint32 constant ETH_PERP_INDEX = 4;
    uint32 constant BTC_PERP_INDEX = 3;
}

// ============ Arbitrum ============

library ArbitrumAddresses {
    // Tokens
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC_NATIVE = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDC_BRIDGED = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    // Uniswap V3
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant SWAP_ROUTER_02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant QUOTER_V2 = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    // Chainlink Price Feeds
    address constant ETH_USD_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant USDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant BTC_USD_FEED = 0x6ce185860A4963106506c203335A58A4Eb8C5f40;

    // Pool Fees
    uint24 constant FEE_LOW = 500;      // 0.05%
    uint24 constant FEE_MEDIUM = 3000;  // 0.3%
    uint24 constant FEE_HIGH = 10000;   // 1%
}

// ============ Chain IDs ============

library ChainIds {
    uint256 constant ARBITRUM_ONE = 42161;
    uint256 constant ARBITRUM_SEPOLIA = 421614;
    uint256 constant HYPEREVM_MAINNET = 999;
    uint256 constant HYPEREVM_TESTNET = 998;
}
