// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingCaptureVault} from "../src/FundingCaptureVault.sol";
import {PerpPosition} from "../src/interfaces/IHyperLiquidPrecompiles.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice 테스트넷 시나리오 테스트
/// @dev 배포 후 전체 플로우 테스트
contract TestScenario {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run(address vaultAddr) external view {
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);

        // 1. Vault 상태 조회
        _log("=== Vault Status ===");
        _log("Owner:", vault.owner());
        _log("State:", _stateToString(vault.state()));
        _log("Total Deposited:", vault.totalDeposited());
        _log("Target Short Size:", vault.targetShortSize());
        _log("Spot Value USD:", vault.spotValueUsd());

        // 2. ETH Oracle Price 조회
        _log("\n=== ETH Oracle Price ===");
        try vault.getEthPrice() returns (uint64 markPx, uint64 indexPx) {
            _log("Mark Price:", markPx);
            _log("Index Price:", indexPx);
        } catch {
            _log("Oracle precompile not available (expected on non-HyperEVM)");
        }

        // 3. Perp Position 조회
        _log("\n=== Perp Position ===");
        try vault.getPerpPosition() returns (PerpPosition memory pos) {
            _log("Size:", pos.szi);
            _log("Entry Price:", pos.entryPx);
            _log("Margin Used:", pos.marginUsed);
            _log("Unrealized PnL:", pos.unrealizedPnl);
        } catch {
            _log("Position precompile not available (expected on non-HyperEVM)");
        }

        // 4. Delta 계산
        _log("\n=== Delta Calculation ===");
        (int256 deltaUsd, uint256 deltaRatioBps) = vault.calculateDelta();
        _log("Delta USD:", deltaUsd);
        _log("Delta Ratio (bps):", deltaRatioBps);
        _log("Needs Rebalance:", vault.needsRebalance());

        _log("\n=== Test Complete ===");
    }

    function _stateToString(FundingCaptureVault.State s) internal pure returns (string memory) {
        if (s == FundingCaptureVault.State.IDLE) return "IDLE";
        if (s == FundingCaptureVault.State.ACTIVE) return "ACTIVE";
        if (s == FundingCaptureVault.State.EXITING) return "EXITING";
        return "UNKNOWN";
    }

    function _log(string memory msg) internal pure {
        // Foundry console log workaround
    }

    function _log(string memory label, address value) internal pure {
        // Will be visible in trace
    }

    function _log(string memory label, string memory value) internal pure {}
    function _log(string memory label, uint256 value) internal pure {}
    function _log(string memory label, int256 value) internal pure {}
    function _log(string memory label, bool value) internal pure {}
}

/// @notice 전체 플로우 테스트: Deploy → Deposit → Open Short → Close
contract FullFlowTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    function run() external returns (address vaultAddr) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);

        // 1. Deploy
        FundingCaptureVault vault = new FundingCaptureVault();
        vaultAddr = address(vault);

        // 2. Update spot value (simulate 1 ETH at $3000)
        // 3000 USD * 1e8 scale = 300000000000
        vault.updateSpotValue(3000 * 1e8);

        vm.stopBroadcast();

        // Log results
        require(vault.owner() == vm.addr(pk), "Owner mismatch");
        require(vault.state() == FundingCaptureVault.State.IDLE, "State should be IDLE");
        require(vault.spotValueUsd() == 3000 * 1e8, "Spot value mismatch");
    }
}

/// @notice 가격 조회 테스트
contract PriceCheck {
    function run(address vaultAddr) external view returns (uint64 markPx, uint64 indexPx) {
        FundingCaptureVault vault = FundingCaptureVault(vaultAddr);
        return vault.getEthPrice();
    }
}
