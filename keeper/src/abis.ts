// FundingCaptureVaultV2 ABI (HyperEVM)
export const FundingCaptureVaultV2Abi = [
  // View Functions
  'function owner() view returns (address)',
  'function state() view returns (uint8)',
  'function spotValueUsd() view returns (uint256)',
  'function perpShortSizeWei() view returns (uint256)',
  'function lastRebalanceTime() view returns (uint256)',
  'function getEthOraclePrice() view returns (uint256)',
  'function getEthMarkPrice() view returns (uint256)',
  'function calculateDelta() view returns (int256 deltaUsd, uint256 deltaRatioBps)',
  'function needsRebalance() view returns (bool)',
  'function ETH_PERP_INDEX() view returns (uint32)',
  'function DELTA_THRESHOLD_BPS() view returns (uint256)',
  'function SLIPPAGE_BPS() view returns (uint256)',
  'function PRICE_DECIMALS() view returns (uint256)',

  // State Changing Functions
  'function updateSpotValue(uint256 newSpotValueUsd)',
  'function openShort(uint256 sizeDeltaWei, uint256 maxSlippageBps)',
  'function closeShort()',
  'function rebalance()',
  'function transferOwnership(address newOwner)',

  // Events
  'event SpotValueUpdated(uint256 oldValue, uint256 newValue)',
  'event ShortOpened(uint256 sizeDeltaWei, uint256 priceUsed)',
  'event ShortClosed(uint256 sizeDeltaWei)',
  'event Rebalanced(int256 deltaBefore, int256 deltaAfter)',
];

// SpotLongVault ABI (Arbitrum)
export const SpotLongVaultAbi = [
  'function owner() view returns (address)',
  'function state() view returns (uint8)',
  'function targetEthAmount() view returns (uint256)',
  'function getWethBalance() view returns (uint256)',
  'function getUsdcBalance() view returns (uint256)',

  'function setTargetEthAmount(uint256 amount)',
  'function buyEth(uint256 usdcAmount, uint256 minEthOut)',
  'function sellEth(uint256 ethAmount, uint256 minUsdcOut)',
  'function deposit() payable',
  'function withdraw(uint256 amount)',
  'function transferOwnership(address newOwner)',
];

// DeltaCoordinator ABI (Arbitrum)
export const DeltaCoordinatorAbi = [
  'function owner() view returns (address)',
  'function keeper() view returns (address)',
  'function spotVault() view returns (address)',
  'function perpShortSizeWei() view returns (uint256)',
  'function perpShortValueUsd() view returns (uint256)',
  'function lastSyncTime() view returns (uint256)',
  'function isStrategyActive() view returns (bool)',
  'function DELTA_THRESHOLD_BPS() view returns (uint256)',
  'function PRICE_STALENESS_THRESHOLD() view returns (uint256)',
  'function MIN_REBALANCE_INTERVAL() view returns (uint256)',

  'function getEthPrice() view returns (uint256 price, uint256 timestamp)',
  'function getSpotValueUsd() view returns (uint256)',
  'function calculateDelta() view returns (int256 deltaUsd, uint256 deltaRatioBps)',
  'function needsRebalance() view returns (bool)',
  'function isPriceValid() view returns (bool)',

  'function syncPerpPosition(uint256 shortSizeWei, uint256 shortValueUsd)',
  'function executeRebalance(uint256 minAmountOut)',
  'function activateStrategy()',
  'function deactivateStrategy()',
  'function setKeeper(address newKeeper)',
  'function transferOwnership(address newOwner)',

  'event PerpPositionSynced(uint256 shortSizeWei, uint256 shortValueUsd, uint256 timestamp)',
  'event DeltaCalculated(int256 deltaUsd, uint256 deltaRatioBps)',
  'event RebalanceTriggered(uint256 spotEthBefore, uint256 spotEthAfter)',
];

// Chainlink Price Feed ABI
export const ChainlinkAggregatorAbi = [
  'function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)',
  'function decimals() view returns (uint8)',
];
