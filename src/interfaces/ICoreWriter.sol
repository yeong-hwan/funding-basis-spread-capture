// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICoreWriter
/// @notice HyperEVM → HyperCore 트랜잭션을 전송하는 시스템 컨트랙트 인터페이스
/// @dev 주소: 0x3333333333333333333333333333333333333333
///      주문/전송 등의 액션은 몇 초 지연됨 (프론트러닝 방지)
interface ICoreWriter {
    /// @notice Raw action 바이트를 HyperCore로 전송
    /// @param data 인코딩된 액션 데이터
    ///        - data[0]: version (현재 0x01)
    ///        - data[1:4]: action ID (little endian)
    ///        - data[4:]: ABI 인코딩된 파라미터
    function sendRawAction(bytes calldata data) external;
}

/// @dev CoreWriter 시스템 컨트랙트 주소 (고정)
address constant CORE_WRITER = 0x3333333333333333333333333333333333333333;
