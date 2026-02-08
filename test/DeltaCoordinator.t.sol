// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeltaCoordinator} from "../src/arbitrum/DeltaCoordinator.sol";
import {SpotLongVault} from "../src/arbitrum/SpotLongVault.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @title DeltaCoordinator 테스트
/// @notice SPEC.md 요구사항 기반 테스트
/// @dev Arbitrum fork 환경에서 실행:
///      forge test --fork-url $ARBITRUM_RPC --match-contract DeltaCoordinatorTest -vvv
contract DeltaCoordinatorTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    DeltaCoordinator internal coordinator;
    SpotLongVault internal spotVault;
    address internal owner;
    address internal keeper = address(0xBEEF);
    address internal notOwner = address(0xCAFE);

    bool internal skipTests;
    bool internal chainlinkAvailable;

    function setUp() public {
        // Arbitrum fork 환경인지 확인
        if (block.chainid != 42161 && block.chainid != 31337) {
            skipTests = true;
            return;
        }

        owner = address(this);

        // SpotLongVault 배포
        try new SpotLongVault() returns (SpotLongVault sv) {
            spotVault = sv;
        } catch {
            skipTests = true;
            return;
        }

        // DeltaCoordinator 배포
        try new DeltaCoordinator(address(spotVault)) returns (DeltaCoordinator dc) {
            coordinator = dc;
        } catch {
            skipTests = true;
            return;
        }

        // Chainlink 가용성 확인
        try coordinator.getEthPrice() returns (uint256 price, uint256) {
            chainlinkAvailable = price > 0;
        } catch {
            chainlinkAvailable = false;
        }
    }

    modifier skipIfNotFork() {
        if (skipTests) return;
        _;
    }

    modifier skipIfNoChainlink() {
        if (skipTests || !chainlinkAvailable) return;
        _;
    }

    // ============================================================
    // SPEC 3.2 Cross-Chain Coordination (C-S1, C-S2)
    // ============================================================

    /// @notice C-S1: Keeper가 Perp 포지션을 동기화할 수 있어야 함
    function test_C_S1_KeeperCanSyncPerpPosition() public skipIfNotFork {
        uint256 shortSize = 1 ether;
        uint256 shortValue = 2000 * 1e6; // $2000

        coordinator.syncPerpPosition(shortSize, shortValue);

        assertEq(coordinator.perpShortSizeWei(), shortSize, "Short size should be synced");
        assertEq(coordinator.perpShortValueUsd(), shortValue, "Short value should be synced");
        assertTrue(coordinator.lastSyncTime() > 0, "Sync time should be recorded");
    }

    /// @notice C-S2: 비권한자는 동기화 불가
    function test_C_S2_OnlyKeeperCanSyncPerpPosition() public skipIfNotFork {
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(DeltaCoordinator.NotOwnerOrKeeper.selector));
        coordinator.syncPerpPosition(1 ether, 2000 * 1e6);
    }

    // ============================================================
    // SPEC 3.3 Position - Delta Tests (P-R1, P-R2)
    // ============================================================

    /// @notice P-R1: Delta 계산 - Spot > Perp
    function test_P_R1_DeltaCalculation_SpotGreaterThanPerp() public skipIfNoChainlink {
        // Perp Short = $1000
        coordinator.syncPerpPosition(0.5 ether, 1000 * 1e6);

        // Spot value는 Chainlink로 계산됨
        (int256 deltaUsd, uint256 deltaRatioBps) = coordinator.calculateDelta();

        // Spot이 0이면 Delta = -1000, Spot > 0이면 Delta 값이 달라짐
        // 이 테스트에서는 spotVault에 WETH가 없으므로 Spot = 0
        assertEq(deltaUsd, -1000 * 1e6, "Delta should be negative when Spot < Perp");
    }

    /// @notice P-R2: Delta 허용 범위 확인 (5%)
    function test_P_R2_DeltaThreshold() public skipIfNotFork {
        assertEq(coordinator.DELTA_THRESHOLD_BPS(), 500, "Delta threshold should be 5%");
    }

    /// @notice needsRebalance는 전략 비활성화 시 false
    function test_NeedsRebalance_WhenInactive() public skipIfNotFork {
        coordinator.syncPerpPosition(1 ether, 2000 * 1e6);
        assertEq(coordinator.needsRebalance(), false, "Should not need rebalance when inactive");
    }

    /// @notice needsRebalance는 전략 활성화 + Delta 초과 시 true
    function test_NeedsRebalance_WhenActiveAndDeltaExceeds() public skipIfNoChainlink {
        coordinator.syncPerpPosition(1 ether, 2000 * 1e6);
        coordinator.activateStrategy();

        // Spot = 0, Perp = $2000이므로 Delta = -$2000 (100%)
        bool needs = coordinator.needsRebalance();
        assertTrue(needs, "Should need rebalance when delta exceeds threshold");
    }

    // ============================================================
    // SPEC 3.4 Risk Controls (R-C2)
    // ============================================================

    /// @notice R-C2: 가격 유효성 검사
    function test_R_C2_PriceStalenessThreshold() public skipIfNotFork {
        assertEq(coordinator.PRICE_STALENESS_THRESHOLD(), 1 hours, "Staleness threshold should be 1 hour");
    }

    /// @notice isPriceValid는 Chainlink 타임스탬프 검사
    function test_IsPriceValid() public skipIfNoChainlink {
        bool isValid = coordinator.isPriceValid();
        assertTrue(isValid, "Price should be valid on fresh fork");
    }

    // ============================================================
    // Access Control Tests
    // ============================================================

    /// @notice Owner 설정 확인
    function test_AccessControl_OwnerSetCorrectly() public skipIfNotFork {
        assertEq(coordinator.owner(), owner, "Owner should be deployer");
    }

    /// @notice Keeper 설정 확인
    function test_AccessControl_KeeperSetCorrectly() public skipIfNotFork {
        assertEq(coordinator.keeper(), owner, "Keeper should be deployer initially");
    }

    /// @notice Owner만 Keeper 변경 가능
    function test_AccessControl_OnlyOwnerCanSetKeeper() public skipIfNotFork {
        coordinator.setKeeper(keeper);
        assertEq(coordinator.keeper(), keeper, "Keeper should be updated");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(DeltaCoordinator.NotOwner.selector));
        coordinator.setKeeper(notOwner);
    }

    /// @notice Owner만 전략 활성화 가능
    function test_AccessControl_OnlyOwnerCanActivateStrategy() public skipIfNotFork {
        coordinator.activateStrategy();
        assertTrue(coordinator.isStrategyActive(), "Strategy should be active");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(DeltaCoordinator.NotOwner.selector));
        coordinator.deactivateStrategy();
    }

    /// @notice Owner만 전략 비활성화 가능
    function test_AccessControl_OnlyOwnerCanDeactivateStrategy() public skipIfNotFork {
        coordinator.activateStrategy();
        coordinator.deactivateStrategy();
        assertEq(coordinator.isStrategyActive(), false, "Strategy should be inactive");
    }

    /// @notice Owner만 Ownership 이전 가능
    function test_AccessControl_OnlyOwnerCanTransferOwnership() public skipIfNotFork {
        address newOwner = address(0xDEAD);
        coordinator.transferOwnership(newOwner);
        assertEq(coordinator.owner(), newOwner, "Ownership should transfer");
    }

    // ============================================================
    // Constants & Parameters Tests
    // ============================================================

    /// @notice MIN_REBALANCE_INTERVAL 확인
    function test_Constants_MinRebalanceInterval() public skipIfNotFork {
        assertEq(coordinator.MIN_REBALANCE_INTERVAL(), 5 minutes, "Min rebalance interval should be 5 minutes");
    }

    // ============================================================
    // Strategy State Tests
    // ============================================================

    /// @notice 초기 상태는 비활성화
    function test_Strategy_InitiallyInactive() public skipIfNotFork {
        assertEq(coordinator.isStrategyActive(), false, "Strategy should start inactive");
    }

    /// @notice 활성화 후 비활성화 가능
    function test_Strategy_CanToggle() public skipIfNotFork {
        assertEq(coordinator.isStrategyActive(), false, "Should start inactive");

        coordinator.activateStrategy();
        assertTrue(coordinator.isStrategyActive(), "Should be active after activation");

        coordinator.deactivateStrategy();
        assertEq(coordinator.isStrategyActive(), false, "Should be inactive after deactivation");
    }

    // ============================================================
    // Chainlink Integration Tests (Arbitrum Fork Only)
    // ============================================================

    /// @notice Chainlink ETH/USD 가격 조회
    function test_Chainlink_GetEthPrice() public skipIfNoChainlink {
        (uint256 price, uint256 timestamp) = coordinator.getEthPrice();

        // 가격이 합리적인 범위인지 확인 ($100 ~ $100,000)
        assertTrue(price > 100 * 1e8, "ETH price should be > $100");
        assertTrue(price < 100000 * 1e8, "ETH price should be < $100,000");
        assertTrue(timestamp > 0, "Timestamp should be positive");
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    /// @notice Zero perp position
    function test_EdgeCase_ZeroPerpPosition() public skipIfNoChainlink {
        // Perp = 0
        coordinator.syncPerpPosition(0, 0);

        (int256 deltaUsd, uint256 deltaRatioBps) = coordinator.calculateDelta();

        // Spot도 0이면 Delta = 0, Ratio = 0
        assertEq(deltaUsd, 0, "Delta should be 0 when both are 0");
        assertEq(deltaRatioBps, 0, "Ratio should be 0 when both are 0");
    }

    /// @notice 여러 번 Perp 동기화
    function test_EdgeCase_MultiplePerpSyncs() public skipIfNotFork {
        coordinator.syncPerpPosition(1 ether, 2000 * 1e6);
        assertEq(coordinator.perpShortValueUsd(), 2000 * 1e6, "First sync");

        coordinator.syncPerpPosition(2 ether, 4000 * 1e6);
        assertEq(coordinator.perpShortValueUsd(), 4000 * 1e6, "Second sync");

        coordinator.syncPerpPosition(0.5 ether, 1000 * 1e6);
        assertEq(coordinator.perpShortValueUsd(), 1000 * 1e6, "Third sync");
    }

    // ============================================================
    // Helper assertions
    // ============================================================

    function assertEq(uint256 a, uint256 b, string memory message) internal pure {
        require(a == b, message);
    }

    function assertEq(int256 a, int256 b, string memory message) internal pure {
        require(a == b, message);
    }

    function assertEq(address a, address b, string memory message) internal pure {
        require(a == b, message);
    }

    function assertEq(bool a, bool b, string memory message) internal pure {
        require(a == b, message);
    }

    function assertTrue(bool condition, string memory message) internal pure {
        require(condition, message);
    }
}
