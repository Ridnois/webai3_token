// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PresaleSystemTestBase } from "./helpers/PresaleSystemTestBase.sol";
import {
    PresaleNotFinalizable,
    PresaleNotActive,
    PauseBudgetExceeded,
    ForceUnpauseUnavailable,
    PhaseCapExceeded,
    HardCapExceeded,
    PresaleNotFinalized,
    LiquidityNotProvisioned,
    ClaimsNotEnabled
} from "../src/presale/PresaleErrors.sol";

contract WebAI3PresaleSystemTest is PresaleSystemTestBase {
    function test_PhaseCapEnforced_NoPartialFill() public {
        _fundAndApprove(alice, 600_000e6);
        vm.expectRevert(PhaseCapExceeded.selector);
        vm.prank(alice);
        presale.buyTokens(600_000e6);
    }

    function test_HardCapEnforced_NoOverflow() public {
        _fillToPhase6();
        assertEq(presale.totalRaisedUSDC(), 6_000_000e6);

        _fundAndApprove(alice, 1_000_001e6);
        vm.expectRevert(HardCapExceeded.selector);
        vm.prank(alice);
        presale.buyTokens(1_000_001e6);
    }

    function test_PermissionlessFinalization_ByTimestamp() public {
        _buy(alice, 10_000e6);

        vm.warp(presaleEnd - 1);
        vm.expectRevert(PresaleNotFinalizable.selector);
        presale.finalizePresale();

        vm.warp(presaleEnd);
        vm.prank(bob);
        presale.finalizePresale();

        assertTrue(presale.presaleFinalized());
    }

    function test_PermissionlessFinalization_ByHardCap() public {
        _fillHardCap();

        vm.prank(carol);
        presale.finalizePresale();

        assertTrue(presale.presaleFinalized());
    }

    function test_PauseBlocksBuys_FinalizeCallableWhilePaused() public {
        vm.prank(pauser);
        presale.pause();

        _fundAndApprove(alice, 1_000e6);
        vm.prank(alice);
        vm.expectRevert(PresaleNotActive.selector);
        presale.buyTokens(1_000e6);

        vm.warp(presaleEnd);
        vm.prank(bob);
        presale.finalizePresale();

        assertTrue(presale.presaleFinalized());
        assertFalse(presale.pauseActive());
    }

    function test_ForceUnpauseAfterSinglePauseExpiry() public {
        vm.prank(pauser);
        presale.pause();

        vm.warp(block.timestamp + 70 hours);
        vm.expectRevert(ForceUnpauseUnavailable.selector);
        presale.forceUnpause();

        vm.warp(block.timestamp + 3 hours);
        presale.forceUnpause();

        assertFalse(presale.pauseActive());
    }

    function test_CumulativePauseBudgetEnforced() public {
        for (uint256 i = 0; i < 4; ++i) {
            vm.prank(pauser);
            presale.pause();
            vm.warp(block.timestamp + 72 hours);
            vm.prank(pauser);
            presale.unpause();
        }

        vm.prank(pauser);
        presale.pause();
        vm.warp(block.timestamp + 48 hours);
        vm.prank(pauser);
        presale.unpause();

        vm.prank(pauser);
        vm.expectRevert(PauseBudgetExceeded.selector);
        presale.pause();
    }

    function test_VaultRouting70_15_10_5() public {
        _buy(alice, 100e6);

        assertEq(liquidityVault.totalDeposited(), 70e6);
        assertEq(devRunwayVault.totalDeposited(), 15e6);
        assertEq(teamStreamVault.totalDeposited(), 10e6);
        assertEq(marketingVault.totalDeposited(), 5e6);

        assertEq(presaleVault.totalRoutedUSDC(), 100e6);
    }

    function test_DevRunwayDualGateLimitsWithdrawals() public {
        _buy(alice, 500_000e6); // dev deposit = 75k, milestone unlock = 50k

        assertEq(devRunwayVault.withdrawableDev(), 0);

        vm.warp(block.timestamp + 10 days);
        assertEq(devRunwayVault.withdrawableDev(), 50_000e6);

        vm.prank(devOperator);
        devRunwayVault.withdraw(50_000e6);

        assertEq(usdc.balanceOf(devBeneficiary), 50_000e6);
        assertEq(devRunwayVault.withdrawableDev(), 0);
    }

    function test_TeamStreamLinearReleaseOnly() public {
        _buy(alice, 100_000e6); // team deposit = 10k USDC

        vm.prank(teamOperator);
        vm.expectRevert();
        teamStreamVault.withdraw(1);

        vm.warp(block.timestamp + 365 days / 2);
        uint256 withdrawable = teamStreamVault.withdrawableAmount();
        assertApproxEqAbs(withdrawable, 5_000e6, 2);

        vm.prank(teamOperator);
        teamStreamVault.withdraw(withdrawable);
        assertEq(usdc.balanceOf(teamBeneficiary), withdrawable);
    }

    function test_MarketingLockedBeforeFinalize_ThenTimelockedAfter() public {
        _buy(alice, 100_000e6);

        vm.prank(marketingOperator);
        vm.expectRevert();
        marketingVault.queueWithdrawal(1_000e6);

        _finalizeByTimestamp();

        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(2_000e6);

        vm.prank(marketingOperator);
        vm.expectRevert();
        marketingVault.executeWithdrawal();

        vm.warp(block.timestamp + 2 days);
        vm.prank(marketingOperator);
        marketingVault.executeWithdrawal();

        assertEq(usdc.balanceOf(marketingBeneficiary), 2_000e6);
    }

    function test_NoClaimsBeforeLiquidityProvisioned() public {
        _buy(alice, 1_000e6);
        _finalizeByTimestamp();

        vm.expectRevert(LiquidityNotProvisioned.selector);
        claimModule.enableClaims();

        vm.expectRevert(ClaimsNotEnabled.selector);
        vm.prank(alice);
        claimModule.claim();
    }

    function test_VestingClaims_30_35_35() public {
        uint256 allocation = _buy(alice, 1_000e6); // 100,000 AIC in phase 1
        assertEq(allocation, 100_000 ether);

        _finalizeByTimestamp();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        claimModule.enableClaims();

        vm.warp(tge - 1);
        assertEq(claimModule.claimableAmount(alice), 0);

        vm.warp(tge);
        vm.prank(alice);
        claimModule.claim();
        assertEq(aic.balanceOf(alice), 30_000 ether);

        vm.warp(tge + 90 days);
        vm.prank(alice);
        claimModule.claim();
        assertEq(aic.balanceOf(alice), 65_000 ether);

        vm.warp(tge + 180 days);
        vm.prank(alice);
        claimModule.claim();
        assertEq(aic.balanceOf(alice), 100_000 ether);
    }

    function test_FallbackLiquidityAfterDelay() public {
        _buy(alice, 250_000e6);
        _finalizeByTimestamp();

        vm.expectRevert();
        liquidityVault.provideLiquidityFallback();

        vm.warp(block.timestamp + liquidityVault.MAX_LIQUIDITY_DELAY() + 1);
        vm.prank(dave);
        liquidityVault.provideLiquidityFallback();

        assertTrue(liquidityVault.liquidityProvisioned());

        claimModule.enableClaims();
        assertTrue(claimModule.claimsEnabled());
    }

    function test_AccountingInvariant_RoutedEqualsVaultTotals() public {
        _buy(alice, 111_000e6);
        _buy(bob, 222_000e6);

        uint256 expected = presale.totalRaisedUSDC();
        uint256 routed = presaleVault.totalRoutedUSDC();
        uint256 sumVaults = liquidityVault.totalDeposited() + devRunwayVault.totalDeposited()
            + teamStreamVault.totalDeposited() + marketingVault.totalDeposited();

        assertEq(routed, expected);
        assertEq(sumVaults, expected);
    }
}
