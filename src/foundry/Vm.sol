// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Foundry cheatcode 주소(고정)
// - Forge 스크립트/테스트 환경에서만 유효합니다.
address constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

/// @notice 필요한 cheatcode만 최소로 선언(외부 의존성 제거 목적)
interface Vm {
    function prank(address caller) external;
    function expectRevert(bytes calldata revertData) external;

    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function envOr(string calldata name, address defaultValue) external returns (address);

    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;

    function addr(uint256 privateKey) external pure returns (address);
}

