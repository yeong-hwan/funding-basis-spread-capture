// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SpotLongVault} from "../src/arbitrum/SpotLongVault.sol";
import {DeltaCoordinator} from "../src/arbitrum/DeltaCoordinator.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice Arbitrum 배포 스크립트 - SpotLongVault
contract DeploySpotVault {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (SpotLongVault vault) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);
        vault = new SpotLongVault();
        vm.stopBroadcast();
    }
}

/// @notice Arbitrum 배포 스크립트 - 전체 시스템
contract DeployArbitrumFull {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (SpotLongVault vault, DeltaCoordinator coordinator) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);

        // 1. SpotLongVault 배포
        vault = new SpotLongVault();

        // 2. DeltaCoordinator 배포
        coordinator = new DeltaCoordinator(address(vault));

        // 3. SpotLongVault의 owner를 Coordinator로 이전 (선택적)
        // vault.transferOwnership(address(coordinator));

        vm.stopBroadcast();
    }
}
