// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SpreadCaptureVault} from "../src/SpreadCaptureVault.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice 배포 스크립트(Arbitrum 등 EVM 호환 체인)
/// @dev `.env`의 환경변수와 `forge script ... --broadcast` 조합으로 사용합니다.
contract Deploy {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (SpreadCaptureVault deployed) {
        // NOTE: 초반에는 "하드코딩/ENV"로 단순하게 가고, 이후 멀티시그/레지스트리로 확장 권장
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        address keeper = vm.envAddress("KEEPER");

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(pk);
        deployed = new SpreadCaptureVault(collateralToken, keeper);
        vm.stopBroadcast();
    }
}

