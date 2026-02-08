// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SpotLongVault} from "../src/arbitrum/SpotLongVault.sol";
import {DeltaCoordinator} from "../src/arbitrum/DeltaCoordinator.sol";

/// @notice Arbitrum 배포 스크립트 - SpotLongVault
/// @dev forge script script/DeployArbitrum.s.sol:DeploySpotVault --rpc-url $ARBITRUM_RPC --broadcast
contract DeploySpotVault is Script {
    function run() external returns (SpotLongVault vault) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(pk);
        vault = new SpotLongVault();
        vm.stopBroadcast();

        console.log("SpotLongVault deployed:", address(vault));
    }
}

/// @notice Arbitrum 배포 스크립트 - 전체 시스템
/// @dev forge script script/DeployArbitrum.s.sol:DeployArbitrumFull --rpc-url $ARBITRUM_RPC --broadcast
contract DeployArbitrumFull is Script {
    function run() external returns (SpotLongVault vault, DeltaCoordinator coordinator) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Arbitrum Full Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(pk);

        // 1. SpotLongVault 배포
        vault = new SpotLongVault();
        console.log("SpotLongVault deployed:", address(vault));

        // 2. DeltaCoordinator 배포
        coordinator = new DeltaCoordinator(address(vault));
        console.log("DeltaCoordinator deployed:", address(coordinator));

        // 3. SpotLongVault의 owner를 Coordinator로 이전 (선택적)
        // vault.transferOwnership(address(coordinator));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("ARBITRUM_SPOT_VAULT=", address(vault));
        console.log("ARBITRUM_COORDINATOR=", address(coordinator));
    }
}
