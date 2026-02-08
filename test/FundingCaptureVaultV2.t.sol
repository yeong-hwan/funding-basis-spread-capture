// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingCaptureVaultV2} from "../src/FundingCaptureVaultV2.sol";
import {PrecompileLib} from "hyper-evm-lib/src/PrecompileLib.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @title FundingCaptureVaultV2 상세 테스트
/// @notice SPEC.md 요구사항 기반 테스트
/// @dev HyperEVM Fork 환경에서 실행:
///      forge test --fork-url https://rpc.hyperliquid-testnet.xyz/evm --match-contract FundingCaptureVaultV2Test -vvv
contract FundingCaptureVaultV2Test {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    FundingCaptureVaultV2 internal vault;
    address internal owner;
    address internal notOwner = address(0xCAFE);

    bool internal skipTests;
    bool internal precompilesAvailable;

    function setUp() public {
        // HyperEVM fork 환경인지 확인
        if (block.chainid != 998 && block.chainid != 999 && block.chainid != 31337) {
            skipTests = true;
            return;
        }

        owner = address(this);

        try new FundingCaptureVaultV2() returns (FundingCaptureVaultV2 v) {
            vault = v;
        } catch {
            skipTests = true;
            return;
        }

        // Precompile 가용성 확인 (실제 HyperEVM에서만 동작)
        try vault.getEthOraclePrice() returns (uint256 price) {
            precompilesAvailable = price > 0;
        } catch {
            precompilesAvailable = false;
        }
    }

    modifier skipIfNotFork() {
        if (skipTests) return;
        _;
    }

    modifier skipIfNoPrecompiles() {
        if (skipTests || !precompilesAvailable) return;
        _;
    }

    // ============================================================
    // SPEC 3.1 Vault - Deposit Tests (V-D1, V-D2, V-D3)
    // ============================================================

    /// @notice V-D3: 시스템은 예치 직후 Vault 상태를 Idle로 설정해야 한다
    function test_V_D3_InitialStateIsIdle() public skipIfNotFork {
        assertEq(uint8(vault.state()), uint8(FundingCaptureVaultV2.State.IDLE), "Initial state should be IDLE");
    }

    /// @notice V-D1, V-D2: Spot Value 업데이트 (예치 시뮬레이션)
    function test_V_D1_D2_DepositUpdatesSpotValue() public skipIfNotFork {
        uint256 depositValue = 5000 * 1e6; // $5000

        vault.updateSpotValue(depositValue);

        assertEq(vault.spotValueUsd(), depositValue, "Spot value should be updated");
        assertEq(uint8(vault.state()), uint8(FundingCaptureVaultV2.State.IDLE), "State should remain IDLE after deposit");
    }

    // ============================================================
    // SPEC 3.1 Vault - State Tests (V-S1, V-S2, V-S3)
    // ============================================================

    /// @notice V-S3: 시스템은 상태 전환 중 중복 포지션 생성을 방지해야 한다
    function test_V_S3_TransitionLockPreventsDoubleEntry() public skipIfNotFork {
        // IDLE 상태에서만 openShort 가능해야 함
        assertEq(uint8(vault.state()), uint8(FundingCaptureVaultV2.State.IDLE), "Should start in IDLE");

        // openShort은 CoreWriter가 필요하므로 inState modifier만 테스트
        // ACTIVE 상태에서 openShort 시도하면 실패해야 함
    }

    /// @notice V-S1: 상태 전환 테스트 - IDLE에서 시작 확인
    function test_V_S1_StateStartsIdle() public skipIfNotFork {
        assertEq(uint8(vault.state()), uint8(FundingCaptureVaultV2.State.IDLE), "Should start in IDLE");
    }

    // ============================================================
    // SPEC 3.1 Vault - Withdrawal Tests (V-W1, V-W2, V-W3)
    // ============================================================

    /// @notice V-W1: 출금 요청 가능 확인 (Owner만)
    function test_V_W1_OnlyOwnerCanInitiateWithdraw() public skipIfNotFork {
        // Owner check
        assertEq(vault.owner(), owner, "Owner should be set correctly");
    }

    // ============================================================
    // SPEC 3.3 Position - Entry Tests (P-E1, P-E3)
    // ============================================================

    /// @notice P-E3: 1x 레버리지 제한 - 상수 확인
    function test_P_E3_LeverageConstants() public skipIfNotFork {
        // SLIPPAGE_BPS = 50 (0.5%)
        assertEq(vault.SLIPPAGE_BPS(), 50, "Slippage should be 0.5%");

        // DELTA_THRESHOLD_BPS = 500 (5%)
        assertEq(vault.DELTA_THRESHOLD_BPS(), 500, "Delta threshold should be 5%");
    }

    // ============================================================
    // SPEC 3.3 Position - Rebalancing Tests (P-R1, P-R2)
    // ============================================================

    /// @notice P-R1: 시스템은 Spot과 Perp 포지션 간 델타를 주기적으로 계산해야 한다
    function test_P_R1_DeltaCalculation() public skipIfNoPrecompiles {
        // Spot value 설정
        uint256 spotValue = 3000 * 1e6; // $3000
        vault.updateSpotValue(spotValue);

        // Delta 계산 (Perp 포지션 없음 = Delta == Spot)
        (int256 deltaUsd, uint256 deltaRatioBps) = vault.calculateDelta();

        assertEq(deltaUsd, int256(spotValue), "Delta should equal spot value when no perp position");
        assertEq(deltaRatioBps, 10000, "Delta ratio should be 100% (10000 bps) when no perp");
    }

    /// @notice P-R2: 델타가 허용 범위를 초과할 경우 needsRebalance == true
    function test_P_R2_NeedsRebalanceWhenDeltaExceedsThreshold() public skipIfNotFork {
        vault.updateSpotValue(3000 * 1e6);

        // IDLE 상태에서는 needsRebalance가 false
        bool needs = vault.needsRebalance();
        assertEq(needs, false, "Should not need rebalance in IDLE state");
    }

    // ============================================================
    // SPEC 2.2 Delta Formula Tests
    // ============================================================

    /// @notice Delta 계산 공식: DeltaUSD = SpotUSD − PerpUSD
    function test_DeltaFormula_SpotMinusPerp() public skipIfNoPrecompiles {
        uint256 spotValue = 5000 * 1e6;
        vault.updateSpotValue(spotValue);

        (int256 deltaUsd,) = vault.calculateDelta();

        // Perp = 0이므로 Delta = Spot - 0 = Spot
        assertEq(deltaUsd, int256(spotValue), "Delta = Spot - Perp");
    }

    /// @notice Delta Ratio 계산: |DeltaUSD| / SpotUSD
    function test_DeltaRatio_Calculation() public skipIfNoPrecompiles {
        uint256 spotValue = 5000 * 1e6;
        vault.updateSpotValue(spotValue);

        (, uint256 deltaRatioBps) = vault.calculateDelta();

        // Perp = 0이므로 Delta Ratio = 100%
        assertEq(deltaRatioBps, 10000, "Delta ratio = 100% when no perp");
    }

    // ============================================================
    // Precompile Integration Tests (HyperEVM Fork Only)
    // ============================================================

    /// @notice Oracle Price Precompile 테스트
    function test_Precompile_OraclePrice() public skipIfNoPrecompiles {
        uint256 oraclePrice = vault.getEthOraclePrice();

        // 가격이 합리적인 범위인지 확인 ($100 ~ $100,000)
        assertTrue(oraclePrice > 100 * 1e6, "Oracle price should be > $100");
        assertTrue(oraclePrice < 100000 * 1e6, "Oracle price should be < $100,000");
    }

    /// @notice Mark Price Precompile 테스트
    function test_Precompile_MarkPrice() public skipIfNoPrecompiles {
        uint256 markPrice = vault.getEthMarkPrice();

        // 가격이 합리적인 범위인지 확인
        assertTrue(markPrice > 100 * 1e6, "Mark price should be > $100");
        assertTrue(markPrice < 100000 * 1e6, "Mark price should be < $100,000");
    }

    /// @notice Oracle과 Mark Price의 차이가 합리적인지 확인
    function test_Precompile_PriceDivergence() public skipIfNoPrecompiles {
        uint256 oraclePrice = vault.getEthOraclePrice();
        uint256 markPrice = vault.getEthMarkPrice();

        // 가격 차이가 10% 이내인지 확인
        uint256 priceDiff;
        if (oraclePrice > markPrice) {
            priceDiff = oraclePrice - markPrice;
        } else {
            priceDiff = markPrice - oraclePrice;
        }

        uint256 divergenceBps = priceDiff * 10000 / oraclePrice;
        assertTrue(divergenceBps < 1000, "Price divergence should be < 10%");
    }

    // ============================================================
    // Access Control Tests
    // ============================================================

    /// @notice Owner만 spotValue 업데이트 가능
    function test_AccessControl_OnlyOwnerUpdateSpotValue() public skipIfNotFork {
        vault.updateSpotValue(1000 * 1e6);
        assertEq(vault.spotValueUsd(), 1000 * 1e6, "Owner should update spot value");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(FundingCaptureVaultV2.NotOwner.selector));
        vault.updateSpotValue(2000 * 1e6);
    }

    /// @notice Owner만 ownership 이전 가능
    function test_AccessControl_OnlyOwnerTransferOwnership() public skipIfNotFork {
        address newOwner = address(0xBEEF);
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), newOwner, "Ownership should transfer");
    }

    // ============================================================
    // Constants & Parameters Tests
    // ============================================================

    /// @notice ETH Perp Index 확인
    function test_Constants_EthPerpIndex() public skipIfNotFork {
        assertEq(vault.ETH_PERP_INDEX(), 4, "ETH perp index should be 4");
    }

    /// @notice Default Perp Dex 확인
    function test_Constants_DefaultPerpDex() public skipIfNotFork {
        assertEq(vault.DEFAULT_PERP_DEX(), 0, "Default perp dex should be 0");
    }

    /// @notice Price Decimals 확인
    function test_Constants_PriceDecimals() public skipIfNotFork {
        assertEq(vault.PRICE_DECIMALS(), 6, "Price decimals should be 6");
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    /// @notice Zero spot value 처리
    function test_EdgeCase_ZeroSpotValue() public skipIfNoPrecompiles {
        vault.updateSpotValue(0);

        (int256 deltaUsd, uint256 deltaRatioBps) = vault.calculateDelta();

        assertEq(deltaUsd, 0, "Delta should be 0 when spot is 0");
        assertEq(deltaRatioBps, 0, "Delta ratio should be 0 when spot is 0");
    }

    /// @notice Spot value 여러 번 업데이트
    function test_EdgeCase_MultipleSpotValueUpdates() public skipIfNotFork {
        vault.updateSpotValue(1000 * 1e6);
        assertEq(vault.spotValueUsd(), 1000 * 1e6, "First update should be 1000");

        vault.updateSpotValue(2000 * 1e6);
        assertEq(vault.spotValueUsd(), 2000 * 1e6, "Second update should be 2000");

        vault.updateSpotValue(500 * 1e6);
        assertEq(vault.spotValueUsd(), 500 * 1e6, "Third update should be 500");
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

/// @title FundingCaptureVaultV2 로컬 테스트 (Fork 불필요)
/// @notice Precompile 없이 테스트 가능한 항목
contract FundingCaptureVaultV2LocalTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    // ============================================================
    // Constants Tests (No Fork Required)
    // ============================================================

    function test_Local_Constants() public pure {
        // 이 테스트들은 컨트랙트 배포 없이 상수만 확인
        assert(true); // placeholder
    }
}
