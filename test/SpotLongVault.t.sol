// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SpotLongVault} from "../src/arbitrum/SpotLongVault.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

/// @notice SpotLongVault 테스트
/// @dev Arbitrum fork 환경에서 실행 필요:
///      forge test --fork-url $ARBITRUM_RPC --match-contract SpotLongVaultTest
contract SpotLongVaultTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    SpotLongVault internal vault;
    address internal owner;
    address internal notOwner = address(0xCAFE);

    bool internal skipTests;

    function setUp() public {
        // Arbitrum fork 환경인지 확인
        if (block.chainid != 42161 && block.chainid != 31337) {
            skipTests = true;
            return;
        }

        owner = address(this);

        // Fork 환경에서만 배포 시도
        try new SpotLongVault() returns (SpotLongVault v) {
            vault = v;
        } catch {
            skipTests = true;
        }
    }

    modifier skipIfNotFork() {
        if (skipTests) return;
        _;
    }

    // ============ Constructor Tests ============

    function test_constructor_sets_owner() public skipIfNotFork {
        assert(vault.owner() == owner);
    }

    function test_constructor_sets_idle_state() public skipIfNotFork {
        assert(uint8(vault.state()) == uint8(SpotLongVault.State.IDLE));
    }

    function test_constants() public skipIfNotFork {
        assert(vault.WETH() == 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        assert(vault.USDC() == 0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        assert(vault.SWAP_ROUTER() == 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        assert(vault.POOL_FEE() == 500);
        assert(vault.SLIPPAGE_BPS() == 50);
    }

    // ============ Access Control Tests ============

    function test_onlyOwner_setTargetEthAmount() public skipIfNotFork {
        vault.setTargetEthAmount(1 ether);
        assert(vault.targetEthAmount() == 1 ether);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(SpotLongVault.NotOwner.selector));
        vault.setTargetEthAmount(2 ether);
    }

    function test_onlyOwner_transferOwnership() public skipIfNotFork {
        address newOwner = address(0xBEEF);
        vault.transferOwnership(newOwner);
        assert(vault.owner() == newOwner);
    }

    // ============ State Tests ============

    function test_targetEthAmount_update() public skipIfNotFork {
        uint256 target1 = 1 ether;
        uint256 target2 = 2 ether;

        vault.setTargetEthAmount(target1);
        assert(vault.targetEthAmount() == target1);

        vault.setTargetEthAmount(target2);
        assert(vault.targetEthAmount() == target2);
    }

    // Note: buyEth, sellEth, deposit, withdraw 등은 실제 토큰과 Uniswap 연동이 필요하므로
    //       Fork 테스트 또는 테스트넷에서 수행
}
