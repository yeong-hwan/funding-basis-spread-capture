// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Perp venue와의 상호작용을 “우리 쪽 관점”으로 표준화한 추상 인터페이스
/// @dev Hyperliquid는 일반적으로 EVM 컨트랙트 호출로만 Perp 주문이 끝나지 않으므로,
///      실제 구현은 오프체인 Keeper(서비스)가 담당하고, 온체인에는 체크포인트를 기록하는 구조가 기본입니다.
interface IPerpVenue {
    /// @dev 포지션 방향(본 전략은 SHORT만 사용)
    enum Side {
        LONG,
        SHORT
    }

    /// @notice 현재 포지션 스냅샷(필요 최소)
    struct PositionView {
        Side side;
        int256 qty; // base 수량(+/-), 구현체 기준에 맞춰 정의
        uint256 notionalUsd; // 포지션 노션(USD/USDT 기준)
        uint256 entryPrice; // 평균 진입가
        uint256 markPrice; // 마크 가격
        int256 unrealizedPnlUsd;
    }

    /// @notice 마진 토큰(USDT) 주소 반환
    function marginToken() external view returns (address);

    /// @notice 특정 마켓(ETH-PERP 등)의 펀딩율 조회(온체인)
    function fundingRateBps(bytes32 marketId) external view returns (int256);

    /// @notice 포지션 조회(온체인)
    function getPosition(bytes32 marketId, address account) external view returns (PositionView memory);

    /// @notice 숏 포지션을 목표 수량으로 맞춤(리밸런싱 핵심)
    /// @dev 체결/슬리피지/주문 타입은 구현체에서 다룸
    function setTargetShortQty(bytes32 marketId, int256 targetQty) external;

    /// @notice 포지션 완전 종료(언와인드)
    function closePosition(bytes32 marketId) external;
}

