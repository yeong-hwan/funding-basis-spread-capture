// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingCaptureVaultV2} from "../src/FundingCaptureVaultV2.sol";
import {PrecompileLib} from "hyper-evm-lib/src/PrecompileLib.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice Fork 테스트 - Precompile 및 Vault 기능 검증
contract ForkTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    FundingCaptureVaultV2 public vault;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // 1. Deploy
        vm.startBroadcast(pk);
        vault = new FundingCaptureVaultV2();
        vm.stopBroadcast();

        // 2. Test Precompile Reads (view functions, no broadcast needed)
        _testPrecompiles();

        // 3. Test Vault State
        _testVaultState(pk);
    }

    function _testPrecompiles() internal view {
        // ETH Oracle Price
        uint256 oraclePrice = vault.getEthOraclePrice();
        require(oraclePrice > 0, "Oracle price should be > 0");

        // ETH Mark Price
        uint256 markPrice = vault.getEthMarkPrice();
        require(markPrice > 0, "Mark price should be > 0");

        // Perp Asset Info
        PrecompileLib.PerpAssetInfo memory info = vault.getPerpAssetInfo();
        require(info.szDecimals > 0, "szDecimals should be > 0");
    }

    function _testVaultState(uint256 pk) internal {
        // Check initial state
        require(vault.state() == FundingCaptureVaultV2.State.IDLE, "Should be IDLE");
        require(vault.owner() == vm.addr(pk), "Owner mismatch");

        // Update spot value
        vm.startBroadcast(pk);
        vault.updateSpotValue(3000 * 1e6); // $3000 (6 decimals)
        vm.stopBroadcast();

        require(vault.spotValueUsd() == 3000 * 1e6, "Spot value mismatch");

        // Calculate delta (should be spot value since no position)
        (int256 deltaUsd, uint256 deltaRatioBps) = vault.calculateDelta();
        require(deltaUsd == int256(3000 * 1e6), "Delta should equal spot value");
    }
}

/// @notice Precompile 전용 테스트
contract PrecompileTest {
    function run() external view {
        // Direct precompile calls
        uint256 ethOraclePrice = PrecompileLib.normalizedOraclePx(4);
        uint256 ethMarkPrice = PrecompileLib.normalizedMarkPx(4);

        PrecompileLib.PerpAssetInfo memory info = PrecompileLib.perpAssetInfo(4);

        // Log results (will show in trace)
        require(ethOraclePrice > 0, "ETH Oracle Price > 0");
        require(ethMarkPrice > 0, "ETH Mark Price > 0");
        require(info.szDecimals == 4, "ETH szDecimals should be 4");
    }
}

/// @notice V2 전체 플로우 시뮬레이션 (Short 포지션 제외 - CoreWriter 필요)
contract V2FlowTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (address vaultAddr) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);

        // 1. Deploy V2
        FundingCaptureVaultV2 vault = new FundingCaptureVaultV2();
        vaultAddr = address(vault);

        // 2. Set spot value ($5000)
        vault.updateSpotValue(5000 * 1e6);

        vm.stopBroadcast();

        // 3. Verify
        require(vault.owner() == vm.addr(pk), "Owner check");
        require(vault.state() == FundingCaptureVaultV2.State.IDLE, "State check");
        require(vault.spotValueUsd() == 5000 * 1e6, "Spot value check");

        // 4. Check prices
        uint256 oraclePrice = vault.getEthOraclePrice();
        uint256 markPrice = vault.getEthMarkPrice();

        require(oraclePrice > 1000 * 1e6, "Oracle price sanity check"); // > $1000
        require(markPrice > 1000 * 1e6, "Mark price sanity check");
    }
}
