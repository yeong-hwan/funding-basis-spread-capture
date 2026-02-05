// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICoreWriter, CORE_WRITER} from "../interfaces/ICoreWriter.sol";

/// @title HyperLiquidActions
/// @notice CoreWriter에 전송할 액션을 인코딩하는 라이브러리
/// @dev Action ID 참고:
///      1 = Limit Order
///      2 = Cancel Order
///      3 = Cancel Order by CLOID
///      7 = USD Class Transfer (Spot ↔ Perp)
library HyperLiquidActions {
    // ============ Constants ============

    /// @dev Action version (현재 0x01)
    uint8 constant ACTION_VERSION = 0x01;

    /// @dev Action IDs
    uint8 constant ACTION_LIMIT_ORDER = 1;
    uint8 constant ACTION_CANCEL_ORDER = 2;
    uint8 constant ACTION_CANCEL_BY_CLOID = 3;
    uint8 constant ACTION_USD_TRANSFER = 7;

    /// @dev Time-in-Force 옵션
    uint8 constant TIF_ALO = 1;  // Add Liquidity Only
    uint8 constant TIF_GTC = 2;  // Good Till Cancel
    uint8 constant TIF_IOC = 3;  // Immediate Or Cancel

    /// @dev Price/Size 스케일 (10^8)
    uint64 constant SCALE = 1e8;

    /// @dev ETH Asset ID (Hyperliquid 기준)
    uint32 constant ETH_ASSET_ID = 3;

    // ============ Order Actions ============

    /// @notice Limit Order 액션 인코딩
    /// @param asset 자산 ID
    /// @param isBuy true=Long, false=Short
    /// @param limitPx 지정가 (10^8 스케일)
    /// @param sz 수량 (10^8 스케일)
    /// @param reduceOnly 포지션 축소만 허용
    /// @param tif Time-in-Force (1=ALO, 2=GTC, 3=IOC)
    /// @param cloid Client Order ID (0이면 없음)
    function encodeLimitOrder(
        uint32 asset,
        bool isBuy,
        uint64 limitPx,
        uint64 sz,
        bool reduceOnly,
        uint8 tif,
        uint128 cloid
    ) internal pure returns (bytes memory) {
        bytes memory params = abi.encode(
            asset,
            isBuy,
            limitPx,
            sz,
            reduceOnly,
            tif,
            cloid
        );

        return _packAction(ACTION_LIMIT_ORDER, params);
    }

    /// @notice Market Order 인코딩 (IOC + slippage 허용가)
    /// @param asset 자산 ID
    /// @param isBuy true=Long, false=Short
    /// @param sz 수량 (10^8 스케일)
    /// @param slippagePx 허용 슬리피지 가격
    /// @param reduceOnly 포지션 축소만 허용
    function encodeMarketOrder(
        uint32 asset,
        bool isBuy,
        uint64 sz,
        uint64 slippagePx,
        bool reduceOnly
    ) internal pure returns (bytes memory) {
        // Market order = IOC limit order at slippage price
        return encodeLimitOrder(
            asset,
            isBuy,
            slippagePx,
            sz,
            reduceOnly,
            TIF_IOC,
            0  // no cloid
        );
    }

    /// @notice Cancel Order 액션 인코딩
    /// @param asset 자산 ID
    /// @param oid Order ID
    function encodeCancelOrder(uint32 asset, uint64 oid) internal pure returns (bytes memory) {
        bytes memory params = abi.encode(asset, oid);
        return _packAction(ACTION_CANCEL_ORDER, params);
    }

    /// @notice Cancel Order by CLOID 액션 인코딩
    /// @param asset 자산 ID
    /// @param cloid Client Order ID
    function encodeCancelByCloid(uint32 asset, uint128 cloid) internal pure returns (bytes memory) {
        bytes memory params = abi.encode(asset, cloid);
        return _packAction(ACTION_CANCEL_BY_CLOID, params);
    }

    // ============ Transfer Actions ============

    /// @notice USD 전송 (Spot ↔ Perp 계정 간)
    /// @param amount 금액 (10^8 스케일)
    /// @param toPerp true=Spot→Perp, false=Perp→Spot
    function encodeUsdTransfer(uint64 amount, bool toPerp) internal pure returns (bytes memory) {
        bytes memory params = abi.encode(amount, toPerp);
        return _packAction(ACTION_USD_TRANSFER, params);
    }

    // ============ Execution Helpers ============

    /// @notice CoreWriter를 통해 액션 실행
    /// @param actionData 인코딩된 액션 데이터
    function execute(bytes memory actionData) internal {
        ICoreWriter(CORE_WRITER).sendRawAction(actionData);
    }

    /// @notice ETH Short 포지션 진입 (Market Order)
    /// @param sz 수량 (10^8 스케일)
    /// @param maxPrice 최대 허용 가격 (슬리피지)
    function openEthShort(uint64 sz, uint64 maxPrice) internal {
        bytes memory action = encodeMarketOrder(
            ETH_ASSET_ID,
            false,      // isBuy = false (Short)
            sz,
            maxPrice,
            false       // not reduce-only
        );
        execute(action);
    }

    /// @notice ETH Short 포지션 청산 (Market Order)
    /// @param sz 청산할 수량 (10^8 스케일)
    /// @param minPrice 최소 허용 가격 (슬리피지)
    function closeEthShort(uint64 sz, uint64 minPrice) internal {
        bytes memory action = encodeMarketOrder(
            ETH_ASSET_ID,
            true,       // isBuy = true (Close Short = Buy)
            sz,
            minPrice,
            true        // reduce-only
        );
        execute(action);
    }

    /// @notice Spot에서 Perp 계정으로 USDC 전송
    /// @param amount 금액 (10^8 스케일)
    function transferToPerp(uint64 amount) internal {
        bytes memory action = encodeUsdTransfer(amount, true);
        execute(action);
    }

    /// @notice Perp에서 Spot 계정으로 USDC 전송
    /// @param amount 금액 (10^8 스케일)
    function transferToSpot(uint64 amount) internal {
        bytes memory action = encodeUsdTransfer(amount, false);
        execute(action);
    }

    // ============ Internal Helpers ============

    /// @dev 액션 헤더 + 파라미터 패킹
    function _packAction(uint8 actionId, bytes memory params) private pure returns (bytes memory) {
        bytes memory data = new bytes(4 + params.length);

        // Header: [version(1)] [actionId(3, little-endian)]
        data[0] = bytes1(ACTION_VERSION);
        data[1] = bytes1(actionId);
        data[2] = 0x00;
        data[3] = 0x00;

        // Copy params
        for (uint256 i = 0; i < params.length; i++) {
            data[4 + i] = params[i];
        }

        return data;
    }
}
