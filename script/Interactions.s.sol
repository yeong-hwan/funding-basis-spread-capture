// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingCaptureVault} from "../src/FundingCaptureVault.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice 테스트넷 인터랙션 스크립트
/// @dev 배포된 Vault와 상호작용
contract Interactions {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    FundingCaptureVault public vault;

    constructor(address _vault) {
        vault = FundingCaptureVault(_vault);
    }

    /// @notice Vault 상태 조회
    function getVaultStatus() external view returns (
        FundingCaptureVault.State state,
        uint64 totalDeposited,
        int64 targetShortSize,
        uint64 spotValueUsd
    ) {
        state = vault.state();
        totalDeposited = vault.totalDeposited();
        targetShortSize = vault.targetShortSize();
        spotValueUsd = vault.spotValueUsd();
    }

    /// @notice ETH 가격 조회
    function getEthPrice() external view returns (uint64 markPx, uint64 indexPx) {
        return vault.getEthPrice();
    }

    /// @notice Delta 조회
    function getDelta() external view returns (int256 deltaUsd, uint256 deltaRatioBps) {
        return vault.calculateDelta();
    }
}

/// @notice Deposit to Perp 스크립트
contract DepositToPerp {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run(address vaultAddr, uint64 amount) external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);

        vm.startBroadcast(pk);
        vault.depositToPerp(amount);
        vm.stopBroadcast();
    }
}

/// @notice Open Short 스크립트
contract OpenShort {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run(address vaultAddr, uint64 size) external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);

        vm.startBroadcast(pk);
        vault.openShort(size);
        vm.stopBroadcast();
    }
}

/// @notice Close Short 스크립트
contract CloseShort {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run(address vaultAddr) external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);

        vm.startBroadcast(pk);
        vault.closeShort();
        vm.stopBroadcast();
    }
}

/// @notice Update Spot Value 스크립트
contract UpdateSpotValue {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run(address vaultAddr, uint64 newSpotValue) external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);

        vm.startBroadcast(pk);
        vault.updateSpotValue(newSpotValue);
        vm.stopBroadcast();
    }
}

/// @notice Rebalance 스크립트
contract Rebalance {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run(address vaultAddr) external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);

        vm.startBroadcast(pk);
        vault.rebalance();
        vm.stopBroadcast();
    }
}
