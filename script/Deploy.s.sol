// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingCaptureVault} from "../src/FundingCaptureVault.sol";
import {FundingCaptureVaultV2} from "../src/FundingCaptureVaultV2.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice HyperEVM 배포 스크립트 (V1)
contract Deploy {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (FundingCaptureVault deployed) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);
        deployed = new FundingCaptureVault();
        vm.stopBroadcast();
    }
}

/// @notice HyperEVM 배포 스크립트 (V2 - 공식 라이브러리 사용)
/// @dev 사용법:
///      1. .env에 DEPLOYER_PRIVATE_KEY 설정
///      2. forge script script/Deploy.s.sol:DeployV2 --rpc-url $HYPEREVM_RPC --broadcast
contract DeployV2 {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (FundingCaptureVaultV2 deployed) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);
        deployed = new FundingCaptureVaultV2();
        vm.stopBroadcast();
    }
}
