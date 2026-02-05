// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IHyperLiquidPrecompiles
/// @notice HyperCore 데이터를 읽기 위한 Precompile 주소 및 인터페이스
/// @dev Precompile 주소는 0x0000000000000000000000000000000000000800부터 시작

// ============ Precompile Addresses ============

/// @dev Base precompile address
address constant PRECOMPILE_BASE = 0x0000000000000000000000000000000000000800;

/// @dev Perp oracle price precompile (asset index 3 = ETH)
address constant PRECOMPILE_PERP_ORACLE_PX = 0x0000000000000000000000000000000000000807;

/// @dev Spot balance precompile
address constant PRECOMPILE_SPOT_BALANCE = 0x0000000000000000000000000000000000000801;

/// @dev Perp position precompile
address constant PRECOMPILE_PERP_POSITION = 0x0000000000000000000000000000000000000802;

/// @dev Perp funding precompile
address constant PRECOMPILE_PERP_FUNDING = 0x0000000000000000000000000000000000000803;

// ============ Data Structures ============

/// @notice Perp 포지션 정보
struct PerpPosition {
    int64 szi;           // 포지션 크기 (양수=Long, 음수=Short)
    uint64 entryPx;      // 진입가 (10^8 스케일)
    uint64 marginUsed;   // 사용 마진
    int64 unrealizedPnl; // 미실현 손익
}

/// @notice Oracle 가격 정보
struct OraclePrice {
    uint64 markPx;       // Mark Price (10^8 스케일)
    uint64 indexPx;      // Index Price (10^8 스케일)
}

// ============ Precompile Interface ============

/// @title IPrecompileReader
/// @notice Precompile 호출을 위한 헬퍼 라이브러리
library PrecompileReader {
    /// @notice ETH Perp의 Oracle Price 조회
    /// @return markPx Mark Price (10^8 스케일)
    /// @return indexPx Index Price (10^8 스케일)
    function getEthOraclePrice() internal view returns (uint64 markPx, uint64 indexPx) {
        // ETH asset index = 3 (Hyperliquid 기준)
        (bool success, bytes memory data) = PRECOMPILE_PERP_ORACLE_PX.staticcall(
            abi.encode(uint32(3))
        );
        require(success, "Oracle precompile failed");
        (markPx, indexPx) = abi.decode(data, (uint64, uint64));
    }

    /// @notice 특정 자산의 Oracle Price 조회
    /// @param assetId 자산 인덱스
    function getOraclePrice(uint32 assetId) internal view returns (uint64 markPx, uint64 indexPx) {
        (bool success, bytes memory data) = PRECOMPILE_PERP_ORACLE_PX.staticcall(
            abi.encode(assetId)
        );
        require(success, "Oracle precompile failed");
        (markPx, indexPx) = abi.decode(data, (uint64, uint64));
    }

    /// @notice Perp 포지션 조회
    /// @param user 유저 주소
    /// @param assetId 자산 인덱스
    function getPerpPosition(address user, uint32 assetId) internal view returns (PerpPosition memory pos) {
        (bool success, bytes memory data) = PRECOMPILE_PERP_POSITION.staticcall(
            abi.encode(user, assetId)
        );
        require(success, "Position precompile failed");
        (pos.szi, pos.entryPx, pos.marginUsed, pos.unrealizedPnl) = abi.decode(
            data,
            (int64, uint64, uint64, int64)
        );
    }

    /// @notice Spot 잔고 조회
    /// @param user 유저 주소
    /// @param tokenIndex 토큰 인덱스
    function getSpotBalance(address user, uint32 tokenIndex) internal view returns (uint64 balance) {
        (bool success, bytes memory data) = PRECOMPILE_SPOT_BALANCE.staticcall(
            abi.encode(user, tokenIndex)
        );
        require(success, "Spot balance precompile failed");
        balance = abi.decode(data, (uint64));
    }
}
