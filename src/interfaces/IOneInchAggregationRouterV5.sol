// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 1inch Aggregation Router(V5 계열) 최소 인터페이스
/// @dev 실제 배포 주소/정확한 시그니처는 체인/버전에 따라 다를 수 있으니, 통합 시점에 검증 필요
interface IAggregationExecutor {
    function callBytes(bytes calldata data) external payable; // 1inch executor 패턴
}

interface IOneInchAggregationRouterV5 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    /// @notice 1inch swap entrypoint(대표 시그니처)
    function swap(
        IAggregationExecutor executor,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}

