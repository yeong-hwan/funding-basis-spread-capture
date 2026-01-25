// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SpreadCaptureVault} from "../src/SpreadCaptureVault.sol";
import {Vm, HEVM_ADDRESS} from "../src/foundry/Vm.sol";

contract SpreadCaptureVaultTest {
    Vm private constant vm = Vm(HEVM_ADDRESS);

    SpreadCaptureVault internal vault;

    address internal owner = address(this);
    address internal keeper = address(0xB0B);
    address internal collateral = address(0xC011A7);

    function setUp() public {
        vault = new SpreadCaptureVault(collateral, keeper);
    }

    function test_constructor_sets_owner_keeper_collateral() public {
        assert(vault.owner() == owner);
        assert(vault.keeper() == keeper);
        assert(vault.collateralToken() == collateral);
    }

    function test_onlyOwner_can_setKeeper() public {
        address newKeeper = address(0xBEEF);
        vault.setKeeper(newKeeper);
        assert(vault.keeper() == newKeeper);

        vm.prank(address(0xCAFE));
        vm.expectRevert(abi.encodeWithSelector(SpreadCaptureVault.NotOwner.selector));
        vault.setKeeper(address(0xABCD));
    }

    function test_onlyKeeper_can_rebalance() public {
        vm.prank(keeper);
        vault.rebalance();

        vm.prank(address(0xCAFE));
        vm.expectRevert(abi.encodeWithSelector(SpreadCaptureVault.NotKeeper.selector));
        vault.rebalance();
    }
}

