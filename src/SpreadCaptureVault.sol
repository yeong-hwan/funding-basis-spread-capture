// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SpreadCaptureVault
/// @notice Spot Long + Perp Short(1x, Cross)로 델타를 중립화하고 Funding 수익을 추구하는 전략의 "금고" 뼈대
/// @dev 실제 거래(현물/퍼프 주문)는 온체인만으로 완결되기 어렵기 때문에,
///      보통 오프체인 Keeper(봇) + 서명/권한 관리 + 이벤트 기록이 핵심이 됩니다.
contract SpreadCaptureVault {
    /// @dev 운영자(초기 배포자). 추후 timelock/멀티시그로 대체 권장
    address public owner;

    /// @dev 오프체인 봇(keeper) 주소. 리밸런싱/정산 트리거 역할
    address public keeper;

    /// @dev 컨트랙트가 관리하는 자산(예: USDC). 이후 명세에 맞춰 확정
    address public collateralToken;

    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);
    event CollateralTokenUpdated(address indexed oldToken, address indexed newToken);

    error NotOwner();
    error NotKeeper();
    error ZeroAddress();

    constructor(address _collateralToken, address _keeper) {
        owner = msg.sender;
        if (_collateralToken == address(0)) revert ZeroAddress();
        if (_keeper == address(0)) revert ZeroAddress();
        collateralToken = _collateralToken;
        keeper = _keeper;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper();
        _;
    }

    /// @notice 운영자 변경
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Keeper(봇) 변경
    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert ZeroAddress();
        emit KeeperUpdated(keeper, newKeeper);
        keeper = newKeeper;
    }

    /// @notice 담보 토큰 변경(전략 변경/업그레이드 시)
    function setCollateralToken(address newToken) external onlyOwner {
        if (newToken == address(0)) revert ZeroAddress();
        emit CollateralTokenUpdated(collateralToken, newToken);
        collateralToken = newToken;
    }

    /// @notice Keeper가 호출하는 "리밸런싱/펀딩 정산" 훅(현재는 이벤트/흐름만 잡아둠)
    /// @dev 실제로는 오프체인에서 Aster/거래소 상태를 보고 주문을 넣은 뒤,
    ///      온체인에는 결과/체크포인트만 기록하거나, 서명 검증을 통해 실행을 승인하는 형태가 유력합니다.
    function rebalance() external onlyKeeper {
        // TODO(명세 확정 후): 델타/레버리지/포지션 가치 체크포인트 업데이트
    }
}

