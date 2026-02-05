// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileLib} from "hyper-evm-lib/src/PrecompileLib.sol";
import {CoreWriterLib} from "hyper-evm-lib/src/CoreWriterLib.sol";
import {HLConstants} from "hyper-evm-lib/src/common/HLConstants.sol";
import {ICoreWriter} from "hyper-evm-lib/src/interfaces/ICoreWriter.sol";

/// @title FundingCaptureVaultV2
/// @notice Delta Neutral 전략으로 Funding Fee를 수취하는 Vault (공식 라이브러리 사용)
/// @dev HyperEVM에 배포되어 CoreWriter를 통해 Perp Short 포지션 관리
contract FundingCaptureVaultV2 {
    // ============ Constants ============

    /// @dev ETH Perp Index (Hyperliquid)
    uint32 public constant ETH_PERP_INDEX = 4;

    /// @dev Default Perp Dex Index
    uint32 public constant DEFAULT_PERP_DEX = 0;

    /// @dev Delta 허용 범위 (5% = 500 basis points)
    uint256 public constant DELTA_THRESHOLD_BPS = 500;

    /// @dev 슬리피지 허용 범위 (0.5% = 50 basis points)
    uint256 public constant SLIPPAGE_BPS = 50;

    /// @dev 가격 정규화 decimals (6)
    uint256 public constant PRICE_DECIMALS = 6;

    // ============ State ============

    enum State {
        IDLE,
        ACTIVE,
        EXITING
    }

    State public state;
    address public owner;

    /// @notice 마지막으로 기록된 Short 수량 (Core 단위)
    int64 public lastShortSize;

    /// @notice Spot Long 가치 (USD, 6 decimals)
    /// @dev Arbitrum의 Spot은 직접 조회 불가하므로 오라클/Keeper가 업데이트
    uint256 public spotValueUsd;

    /// @notice 마지막 리밸런싱 시각
    uint256 public lastRebalanceTime;

    // ============ Events ============

    event ShortOpened(int64 size, uint256 price);
    event ShortClosed(int64 size, uint256 price);
    event Rebalanced(int64 oldSize, int64 newSize);
    event StateChanged(State oldState, State newState);
    event SpotValueUpdated(uint256 oldValue, uint256 newValue);
    event UsdcBridgedToCore(uint256 amount);

    // ============ Errors ============

    error NotOwner();
    error InvalidState(State current, State required);
    error DeltaWithinThreshold();
    error ZeroAmount();
    error NoPosition();

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier inState(State required) {
        if (state != required) revert InvalidState(state, required);
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
        state = State.IDLE;
    }

    // ============ View Functions ============

    /// @notice ETH Oracle Price 조회 (6 decimals로 정규화)
    function getEthOraclePrice() public view returns (uint256) {
        return PrecompileLib.normalizedOraclePx(ETH_PERP_INDEX);
    }

    /// @notice ETH Mark Price 조회 (6 decimals로 정규화)
    function getEthMarkPrice() public view returns (uint256) {
        return PrecompileLib.normalizedMarkPx(ETH_PERP_INDEX);
    }

    /// @notice 현재 Perp 포지션 조회
    function getPerpPosition() public view returns (PrecompileLib.Position memory) {
        return PrecompileLib.position(address(this), uint16(ETH_PERP_INDEX));
    }

    /// @notice ETH Perp Asset Info 조회
    function getPerpAssetInfo() public view returns (PrecompileLib.PerpAssetInfo memory) {
        return PrecompileLib.perpAssetInfo(ETH_PERP_INDEX);
    }

    /// @notice Delta 계산
    /// @return deltaUsd Delta (USD, 6 decimals)
    /// @return deltaRatioBps Delta 비율 (basis points)
    function calculateDelta() public view returns (int256 deltaUsd, uint256 deltaRatioBps) {
        PrecompileLib.Position memory pos = getPerpPosition();
        uint256 markPx = getEthMarkPrice();

        // Perp Notional (절대값) - size * price / 10^6
        uint256 perpNotional;
        if (pos.szi < 0) {
            perpNotional = uint256(uint64(-pos.szi)) * markPx / 1e6;
        } else {
            perpNotional = uint256(uint64(pos.szi)) * markPx / 1e6;
        }

        // Delta = Spot - Perp
        deltaUsd = int256(spotValueUsd) - int256(perpNotional);

        // Delta Ratio = |Delta| / Spot (basis points)
        if (spotValueUsd > 0) {
            uint256 absDelta = deltaUsd < 0 ? uint256(-deltaUsd) : uint256(deltaUsd);
            deltaRatioBps = absDelta * 10000 / spotValueUsd;
        }
    }

    /// @notice 리밸런싱 필요 여부
    function needsRebalance() public view returns (bool) {
        if (state != State.ACTIVE) return false;
        (, uint256 deltaRatioBps) = calculateDelta();
        return deltaRatioBps > DELTA_THRESHOLD_BPS;
    }

    /// @notice Account Margin Summary 조회
    function getAccountMargin() public view returns (PrecompileLib.AccountMarginSummary memory) {
        return PrecompileLib.accountMarginSummary(DEFAULT_PERP_DEX, address(this));
    }

    // ============ Owner Functions ============

    /// @notice Spot 가치 업데이트 (오프체인 Keeper가 호출)
    function updateSpotValue(uint256 newSpotValue) external onlyOwner {
        emit SpotValueUpdated(spotValueUsd, newSpotValue);
        spotValueUsd = newSpotValue;
    }

    /// @notice USDC를 Core의 Perp 계정으로 브릿지
    /// @param evmAmount EVM USDC 금액 (6 decimals)
    function bridgeUsdcToPerp(uint256 evmAmount) external onlyOwner {
        if (evmAmount == 0) revert ZeroAmount();

        // EVM USDC → Core Perp Dex
        CoreWriterLib.bridgeUsdcToCoreFor(
            address(this),
            evmAmount,
            HLConstants.DEFAULT_PERP_DEX
        );

        emit UsdcBridgedToCore(evmAmount);
    }

    /// @notice Short 포지션 진입
    /// @param sizeWei 수량 (Core 단위, szDecimals 적용)
    function openShort(uint64 sizeWei) external onlyOwner inState(State.IDLE) {
        if (sizeWei == 0) revert ZeroAmount();

        uint256 oraclePx = getEthOraclePrice();

        // 슬리피지 적용 (Short은 낮은 가격에 팔게 되므로 limit price를 낮게)
        uint64 limitPx = uint64(oraclePx * (10000 - SLIPPAGE_BPS) / 10000);

        // IOC Market Order로 Short 진입
        _placeOrder(
            ETH_PERP_INDEX,
            false,      // isBuy = false (Short)
            limitPx,
            sizeWei,
            false,      // not reduce-only
            HLConstants.LIMIT_ORDER_TIF_IOC
        );

        lastShortSize = -int64(sizeWei);
        _setState(State.ACTIVE);

        emit ShortOpened(-int64(sizeWei), oraclePx);
    }

    /// @notice Short 포지션 청산
    function closeShort() external onlyOwner inState(State.ACTIVE) {
        PrecompileLib.Position memory pos = getPerpPosition();
        if (pos.szi >= 0) revert NoPosition();

        uint256 oraclePx = getEthOraclePrice();

        // 슬리피지 적용 (Buy는 높은 가격에 사게 되므로 limit price를 높게)
        uint64 limitPx = uint64(oraclePx * (10000 + SLIPPAGE_BPS) / 10000);
        uint64 closeSize = uint64(-pos.szi);

        // IOC Market Order로 청산
        _placeOrder(
            ETH_PERP_INDEX,
            true,       // isBuy = true (Close Short)
            limitPx,
            closeSize,
            true,       // reduce-only
            HLConstants.LIMIT_ORDER_TIF_IOC
        );

        emit ShortClosed(pos.szi, oraclePx);
        _setState(State.EXITING);
    }

    /// @notice 리밸런싱 (Delta 조정)
    function rebalance() external onlyOwner inState(State.ACTIVE) {
        (, uint256 deltaRatioBps) = calculateDelta();
        if (deltaRatioBps <= DELTA_THRESHOLD_BPS) revert DeltaWithinThreshold();

        PrecompileLib.Position memory pos = getPerpPosition();
        uint256 oraclePx = getEthOraclePrice();

        // 목표 Perp 수량 = Spot Value / Oracle Price (음수로 Short)
        // spotValueUsd는 6 decimals, oraclePx도 6 decimals
        int64 targetSize = -int64(uint64(spotValueUsd * 1e6 / oraclePx));
        int64 currentSize = pos.szi;
        int64 adjustment = targetSize - currentSize;

        if (adjustment < 0) {
            // Short 추가 (더 많이 팔기)
            uint64 addSize = uint64(-adjustment);
            uint64 limitPx = uint64(oraclePx * (10000 - SLIPPAGE_BPS) / 10000);
            _placeOrder(ETH_PERP_INDEX, false, limitPx, addSize, false, HLConstants.LIMIT_ORDER_TIF_IOC);
        } else if (adjustment > 0) {
            // Short 축소 (일부 사기)
            uint64 reduceSize = uint64(adjustment);
            uint64 limitPx = uint64(oraclePx * (10000 + SLIPPAGE_BPS) / 10000);
            _placeOrder(ETH_PERP_INDEX, true, limitPx, reduceSize, true, HLConstants.LIMIT_ORDER_TIF_IOC);
        }

        emit Rebalanced(currentSize, targetSize);
        lastRebalanceTime = block.timestamp;
        lastShortSize = targetSize;
    }

    /// @notice 청산 완료 후 IDLE로 복귀
    function finalizeExit() external onlyOwner inState(State.EXITING) {
        PrecompileLib.Position memory pos = getPerpPosition();
        require(pos.szi == 0, "Position not fully closed");

        lastShortSize = 0;
        _setState(State.IDLE);
    }

    /// @notice Owner 변경
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    // ============ Internal ============

    function _setState(State newState) internal {
        emit StateChanged(state, newState);
        state = newState;
    }

    /// @notice CoreWriter를 통해 Limit Order 전송
    function _placeOrder(
        uint32 asset,
        bool isBuy,
        uint64 limitPx,
        uint64 sz,
        bool reduceOnly,
        uint8 tif
    ) internal {
        ICoreWriter coreWriter = ICoreWriter(0x3333333333333333333333333333333333333333);

        // Action encoding: [version(1)][actionId(3)][params...]
        bytes memory action = abi.encodePacked(
            uint8(0x01),                        // version
            HLConstants.LIMIT_ORDER_ACTION,     // actionId (uint24)
            abi.encode(
                asset,
                isBuy,
                limitPx,
                sz,
                reduceOnly,
                tif,
                uint128(0)  // cloid
            )
        );

        coreWriter.sendRawAction(action);
    }
}
