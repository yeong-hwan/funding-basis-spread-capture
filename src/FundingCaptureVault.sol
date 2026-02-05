// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileReader, PerpPosition} from "./interfaces/IHyperLiquidPrecompiles.sol";
import {HyperLiquidActions} from "./libraries/HyperLiquidActions.sol";

/// @title FundingCaptureVault
/// @notice Delta Neutral 전략으로 Funding Fee를 수취하는 Vault
/// @dev HyperEVM에 배포되어 CoreWriter를 통해 Perp Short 포지션 관리
///      Spot Long은 별도 체인(Arbitrum)에서 수동 관리
contract FundingCaptureVault {
    using HyperLiquidActions for *;

    // ============ Constants ============

    /// @dev ETH Asset ID
    uint32 public constant ETH_ASSET_ID = 3;

    /// @dev 가격/수량 스케일 (10^8)
    uint64 public constant SCALE = 1e8;

    /// @dev Delta 허용 범위 (5% = 500 basis points)
    uint256 public constant DELTA_THRESHOLD_BPS = 500;

    /// @dev 슬리피지 허용 범위 (0.5% = 50 basis points)
    uint256 public constant SLIPPAGE_BPS = 50;

    // ============ State ============

    /// @notice Vault 상태
    enum State {
        IDLE,       // 포지션 없음, 대기 중
        ACTIVE,     // 포지션 활성화
        EXITING     // 청산 진행 중
    }

    /// @notice 현재 상태
    State public state;

    /// @notice Owner (관리자)
    address public owner;

    /// @notice 예치된 총 USDC (10^8 스케일)
    uint64 public totalDeposited;

    /// @notice Short 포지션 목표 수량 (10^8 스케일, 음수)
    int64 public targetShortSize;

    /// @notice 마지막 리밸런싱 시각
    uint256 public lastRebalanceTime;

    /// @notice Spot Long 가치 (오프체인에서 업데이트, 10^8 스케일)
    /// @dev Arbitrum의 Spot은 직접 조회 불가하므로 오라클/Keeper가 업데이트
    uint64 public spotValueUsd;

    // ============ Events ============

    event Deposited(address indexed user, uint64 amount);
    event Withdrawn(address indexed user, uint64 amount);
    event ShortOpened(int64 size, uint64 price);
    event ShortClosed(int64 size, uint64 price);
    event Rebalanced(int64 oldSize, int64 newSize);
    event StateChanged(State oldState, State newState);
    event SpotValueUpdated(uint64 oldValue, uint64 newValue);

    // ============ Errors ============

    error NotOwner();
    error InvalidState(State current, State required);
    error InsufficientBalance();
    error DeltaWithinThreshold();
    error ZeroAmount();

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

    /// @notice 현재 ETH Oracle Price 조회
    /// @return markPx Mark Price (10^8 스케일)
    /// @return indexPx Index Price (10^8 스케일)
    function getEthPrice() public view returns (uint64 markPx, uint64 indexPx) {
        return PrecompileReader.getEthOraclePrice();
    }

    /// @notice 현재 Perp 포지션 조회
    function getPerpPosition() public view returns (PerpPosition memory) {
        return PrecompileReader.getPerpPosition(address(this), ETH_ASSET_ID);
    }

    /// @notice Delta 계산 (Spot - |Perp|)
    /// @return deltaUsd Delta (USD, 10^8 스케일)
    /// @return deltaRatioBps Delta 비율 (basis points)
    function calculateDelta() public view returns (int256 deltaUsd, uint256 deltaRatioBps) {
        PerpPosition memory pos = getPerpPosition();
        (uint64 markPx,) = getEthPrice();

        // Perp Notional (절대값)
        uint256 perpNotional = uint256(uint64(pos.szi < 0 ? -pos.szi : pos.szi)) * markPx / SCALE;

        // Delta = Spot - Perp
        deltaUsd = int256(uint256(spotValueUsd)) - int256(perpNotional);

        // Delta Ratio = |Delta| / Spot (basis points)
        if (spotValueUsd > 0) {
            deltaRatioBps = (deltaUsd < 0 ? uint256(-deltaUsd) : uint256(deltaUsd)) * 10000 / spotValueUsd;
        }
    }

    /// @notice 리밸런싱 필요 여부
    function needsRebalance() public view returns (bool) {
        if (state != State.ACTIVE) return false;
        (, uint256 deltaRatioBps) = calculateDelta();
        return deltaRatioBps > DELTA_THRESHOLD_BPS;
    }

    // ============ Owner Functions ============

    /// @notice Spot 가치 업데이트 (오프체인 Keeper가 호출)
    /// @param newSpotValue 새로운 Spot 가치 (USD, 10^8 스케일)
    function updateSpotValue(uint64 newSpotValue) external onlyOwner {
        emit SpotValueUpdated(spotValueUsd, newSpotValue);
        spotValueUsd = newSpotValue;
    }

    /// @notice USDC를 Perp 계정으로 전송
    /// @param amount 금액 (10^8 스케일)
    function depositToPerp(uint64 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        HyperLiquidActions.transferToPerp(amount);
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Short 포지션 진입
    /// @param size 수량 (10^8 스케일)
    function openShort(uint64 size) external onlyOwner inState(State.IDLE) {
        if (size == 0) revert ZeroAmount();

        (uint64 markPx,) = getEthPrice();

        // 슬리피지 적용한 최대 가격 (Short이므로 낮은 가격이 불리)
        uint64 maxPrice = uint64(uint256(markPx) * (10000 + SLIPPAGE_BPS) / 10000);

        HyperLiquidActions.openEthShort(size, maxPrice);

        targetShortSize = -int64(size);
        _setState(State.ACTIVE);

        emit ShortOpened(-int64(size), markPx);
    }

    /// @notice Short 포지션 청산
    function closeShort() external onlyOwner inState(State.ACTIVE) {
        PerpPosition memory pos = getPerpPosition();
        if (pos.szi >= 0) revert InsufficientBalance();

        (uint64 markPx,) = getEthPrice();

        // 슬리피지 적용한 최소 가격 (Buy이므로 높은 가격이 불리)
        uint64 minPrice = uint64(uint256(markPx) * (10000 - SLIPPAGE_BPS) / 10000);

        uint64 closeSize = uint64(-pos.szi);
        HyperLiquidActions.closeEthShort(closeSize, minPrice);

        emit ShortClosed(pos.szi, markPx);
        _setState(State.EXITING);
    }

    /// @notice 리밸런싱 (Delta 조정)
    function rebalance() external onlyOwner inState(State.ACTIVE) {
        (, uint256 deltaRatioBps) = calculateDelta();
        if (deltaRatioBps <= DELTA_THRESHOLD_BPS) revert DeltaWithinThreshold();

        PerpPosition memory pos = getPerpPosition();
        (uint64 markPx,) = getEthPrice();

        // 목표 Perp 수량 = Spot Value / Mark Price
        int64 targetSize = -int64(uint64(spotValueUsd * SCALE / markPx));
        int64 currentSize = pos.szi;
        int64 adjustment = targetSize - currentSize;

        if (adjustment < 0) {
            // Short 추가 (더 많이 팔기)
            uint64 addSize = uint64(-adjustment);
            uint64 maxPrice = uint64(uint256(markPx) * (10000 + SLIPPAGE_BPS) / 10000);
            HyperLiquidActions.openEthShort(addSize, maxPrice);
        } else if (adjustment > 0) {
            // Short 축소 (일부 사기)
            uint64 reduceSize = uint64(adjustment);
            uint64 minPrice = uint64(uint256(markPx) * (10000 - SLIPPAGE_BPS) / 10000);
            HyperLiquidActions.closeEthShort(reduceSize, minPrice);
        }

        emit Rebalanced(currentSize, targetSize);
        lastRebalanceTime = block.timestamp;
        targetShortSize = targetSize;
    }

    /// @notice 청산 완료 후 Idle로 복귀
    function finalizeExit() external onlyOwner inState(State.EXITING) {
        PerpPosition memory pos = getPerpPosition();
        // 포지션이 완전히 청산되었는지 확인
        require(pos.szi == 0, "Position not fully closed");

        targetShortSize = 0;
        _setState(State.IDLE);
    }

    /// @notice USDC를 Spot 계정으로 출금
    /// @param amount 금액 (10^8 스케일)
    function withdrawToSpot(uint64 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > totalDeposited) revert InsufficientBalance();

        HyperLiquidActions.transferToSpot(amount);
        totalDeposited -= amount;

        emit Withdrawn(msg.sender, amount);
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
}
