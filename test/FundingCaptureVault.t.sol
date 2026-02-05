// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FundingCaptureVault} from "../src/FundingCaptureVault.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice FundingCaptureVault 테스트
/// @dev HyperEVM Precompile은 로컬에서 동작하지 않으므로
///      Unit test는 상태 전이 및 접근 제어만 테스트
///      통합 테스트는 테스트넷에서 수행
contract FundingCaptureVaultTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    FundingCaptureVault internal vault;
    address internal owner;
    address internal notOwner = address(0xCAFE);

    function setUp() public {
        owner = address(this);
        vault = new FundingCaptureVault();
    }

    // ============ Constructor Tests ============

    function test_constructor_sets_owner() public view {
        assert(vault.owner() == owner);
    }

    function test_constructor_sets_idle_state() public view {
        assert(uint8(vault.state()) == uint8(FundingCaptureVault.State.IDLE));
    }

    // ============ Access Control Tests ============

    function test_onlyOwner_updateSpotValue() public {
        vault.updateSpotValue(1000 * 1e8);
        assert(vault.spotValueUsd() == 1000 * 1e8);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(FundingCaptureVault.NotOwner.selector));
        vault.updateSpotValue(2000 * 1e8);
    }

    function test_onlyOwner_transferOwnership() public {
        address newOwner = address(0xBEEF);
        vault.transferOwnership(newOwner);
        assert(vault.owner() == newOwner);
    }

    // ============ State Tests ============

    function test_spotValue_update() public {
        uint64 value1 = 5000 * 1e8;
        uint64 value2 = 6000 * 1e8;

        vault.updateSpotValue(value1);
        assert(vault.spotValueUsd() == value1);

        vault.updateSpotValue(value2);
        assert(vault.spotValueUsd() == value2);
    }

    // ============ Constants Tests ============

    function test_constants() public view {
        assert(vault.ETH_ASSET_ID() == 3);
        assert(vault.SCALE() == 1e8);
        assert(vault.DELTA_THRESHOLD_BPS() == 500);
        assert(vault.SLIPPAGE_BPS() == 50);
    }

    // Note: openShort, closeShort, rebalance 등은 HyperEVM Precompile/CoreWriter가
    // 필요하므로 테스트넷 통합 테스트에서 수행
}
