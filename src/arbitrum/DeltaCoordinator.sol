// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainlinkAggregator, ChainlinkFeeds} from "./interfaces/IChainlinkOracle.sol";
import {SpotLongVault} from "./SpotLongVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DeltaCoordinator
/// @notice Delta Neutral 전략의 Spot 측 조정을 담당
/// @dev Chainlink 오라클로 가격 조회, SpotLongVault 제어
contract DeltaCoordinator {
    // ============ Constants ============

    /// @dev Delta 허용 범위 (5% = 500 basis points)
    uint256 public constant DELTA_THRESHOLD_BPS = 500;

    /// @dev 가격 유효 시간 (1시간)
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours;

    /// @dev 최소 리밸런싱 간격 (5분)
    uint256 public constant MIN_REBALANCE_INTERVAL = 5 minutes;

    // ============ State ============

    /// @notice Owner
    address public owner;

    /// @notice Keeper (자동화 봇)
    address public keeper;

    /// @notice SpotLongVault 주소
    SpotLongVault public spotVault;

    /// @notice HyperEVM Perp Vault의 Short 수량 (wei 단위로 환산)
    /// @dev Keeper가 주기적으로 업데이트 (크로스체인 조회 불가)
    uint256 public perpShortSizeWei;

    /// @notice Perp Short의 USD 가치 (6 decimals)
    uint256 public perpShortValueUsd;

    /// @notice 마지막 동기화 시각
    uint256 public lastSyncTime;

    /// @notice 전략 활성화 여부
    bool public isStrategyActive;

    // ============ Events ============

    event PerpPositionSynced(uint256 shortSizeWei, uint256 shortValueUsd, uint256 timestamp);
    event DeltaCalculated(int256 deltaUsd, uint256 deltaRatioBps);
    event RebalanceTriggered(uint256 spotEthBefore, uint256 spotEthAfter);
    event StrategyActivated();
    event StrategyDeactivated();
    event KeeperUpdated(address oldKeeper, address newKeeper);

    // ============ Errors ============

    error NotOwner();
    error NotKeeper();
    error NotOwnerOrKeeper();
    error StrategyNotActive();
    error PriceStale();
    error DeltaWithinThreshold();
    error RebalanceTooFrequent();

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner) revert NotOwnerOrKeeper();
        _;
    }

    modifier whenActive() {
        if (!isStrategyActive) revert StrategyNotActive();
        _;
    }

    // ============ Constructor ============

    constructor(address _spotVault) {
        owner = msg.sender;
        keeper = msg.sender;
        spotVault = SpotLongVault(payable(_spotVault));
    }

    // ============ View Functions ============

    /// @notice ETH/USD 가격 조회 (Chainlink)
    /// @return price 가격 (8 decimals)
    /// @return timestamp 업데이트 시각
    function getEthPrice() public view returns (uint256 price, uint256 timestamp) {
        IChainlinkAggregator feed = IChainlinkAggregator(ChainlinkFeeds.ETH_USD);
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        price = uint256(answer);
        timestamp = updatedAt;
    }

    /// @notice Spot Long 가치 계산 (USD, 6 decimals)
    function getSpotValueUsd() public view returns (uint256) {
        uint256 wethBalance = spotVault.getWethBalance();
        (uint256 ethPrice,) = getEthPrice();

        // wethBalance (18 decimals) * ethPrice (8 decimals) / 1e18 / 1e2 = 6 decimals
        return wethBalance * ethPrice / 1e20;
    }

    /// @notice Delta 계산
    /// @return deltaUsd Delta (Spot - Perp), 6 decimals, signed
    /// @return deltaRatioBps Delta 비율 (basis points)
    function calculateDelta() public view returns (int256 deltaUsd, uint256 deltaRatioBps) {
        uint256 spotValue = getSpotValueUsd();

        // Delta = Spot - |Perp| (Perp는 Short이므로 절대값)
        deltaUsd = int256(spotValue) - int256(perpShortValueUsd);

        // Delta Ratio = |Delta| / max(Spot, Perp)
        uint256 maxValue = spotValue > perpShortValueUsd ? spotValue : perpShortValueUsd;
        if (maxValue > 0) {
            uint256 absDelta = deltaUsd < 0 ? uint256(-deltaUsd) : uint256(deltaUsd);
            deltaRatioBps = absDelta * 10000 / maxValue;
        }
    }

    /// @notice 리밸런싱 필요 여부
    function needsRebalance() public view returns (bool) {
        if (!isStrategyActive) return false;

        (, uint256 deltaRatioBps) = calculateDelta();
        return deltaRatioBps > DELTA_THRESHOLD_BPS;
    }

    /// @notice 가격 유효성 검사
    function isPriceValid() public view returns (bool) {
        (, uint256 timestamp) = getEthPrice();
        return block.timestamp - timestamp <= PRICE_STALENESS_THRESHOLD;
    }

    // ============ Keeper Functions ============

    /// @notice Perp 포지션 동기화 (Keeper가 HyperEVM에서 조회 후 호출)
    /// @param shortSizeWei Short 수량 (wei)
    /// @param shortValueUsd Short 가치 (USD, 6 decimals)
    function syncPerpPosition(uint256 shortSizeWei, uint256 shortValueUsd) external onlyKeeper {
        perpShortSizeWei = shortSizeWei;
        perpShortValueUsd = shortValueUsd;
        lastSyncTime = block.timestamp;

        emit PerpPositionSynced(shortSizeWei, shortValueUsd, block.timestamp);
    }

    /// @notice 자동 리밸런싱 실행
    /// @param minAmountOut 최소 출력 금액
    function executeRebalance(uint256 minAmountOut) external onlyKeeper whenActive {
        if (!isPriceValid()) revert PriceStale();

        (int256 deltaUsd, uint256 deltaRatioBps) = calculateDelta();
        if (deltaRatioBps <= DELTA_THRESHOLD_BPS) revert DeltaWithinThreshold();

        emit DeltaCalculated(deltaUsd, deltaRatioBps);

        uint256 spotEthBefore = spotVault.getWethBalance();

        // Spot 조정
        (uint256 ethPrice,) = getEthPrice();

        if (deltaUsd > 0) {
            // Spot > Perp: ETH 일부 매도
            uint256 excessUsd = uint256(deltaUsd);
            uint256 ethToSell = excessUsd * 1e20 / ethPrice; // 6 decimals → 18 decimals

            if (ethToSell > 0 && ethToSell <= spotEthBefore) {
                spotVault.sellEth(ethToSell, minAmountOut);
            }
        } else {
            // Spot < Perp: ETH 추가 매수
            uint256 deficitUsd = uint256(-deltaUsd);
            // deficitUsd는 6 decimals (USDC)
            uint256 usdcToSpend = deficitUsd;

            if (usdcToSpend > 0) {
                uint256 minEthOut = usdcToSpend * 1e20 / ethPrice * 95 / 100; // 5% slippage
                spotVault.buyEth(usdcToSpend, minEthOut);
            }
        }

        uint256 spotEthAfter = spotVault.getWethBalance();
        emit RebalanceTriggered(spotEthBefore, spotEthAfter);
    }

    // ============ Owner Functions ============

    /// @notice 전략 활성화
    function activateStrategy() external onlyOwner {
        isStrategyActive = true;
        emit StrategyActivated();
    }

    /// @notice 전략 비활성화
    function deactivateStrategy() external onlyOwner {
        isStrategyActive = false;
        emit StrategyDeactivated();
    }

    /// @notice Keeper 주소 변경
    function setKeeper(address newKeeper) external onlyOwner {
        emit KeeperUpdated(keeper, newKeeper);
        keeper = newKeeper;
    }

    /// @notice SpotVault 주소 변경
    function setSpotVault(address newVault) external onlyOwner {
        spotVault = SpotLongVault(payable(newVault));
    }

    /// @notice Owner 변경
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}
