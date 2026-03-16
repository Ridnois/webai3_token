// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PresaleSystemTestBase } from "./helpers/PresaleSystemTestBase.sol";
import {
    WithdrawalExceedsLimit,
    ZeroAmount,
    NotAuthorized,
    MarketingLocked,
    TimelockNotReady,
    NoQueuedWithdrawal,
    InvalidConfiguration,
    PresaleNotFinalized,
    LiquidityAlreadyProvisioned,
    LiquidityWindowExpired,
    LiquidityFallbackNotAvailable
} from "../src/presale/PresaleErrors.sol";

/// @notice Tests covering every vault's withdrawal rules.
///
/// DevRunwayVault  — stream-only gating from day one
/// TeamStreamVault — linear stream over configurable duration
/// MarketingVault  — locked pre-finalization, then timelock queue → execute
/// LiquidityVault  — primary role path + permissionless fallback after 7 days
contract VaultWithdrawalsTest is PresaleSystemTestBase {
    // ─── helpers ────────────────────────────────────────────────────────────

    /// Seed all vaults by making a presale buy.
    function _seedVaults(uint256 usdcAmount) internal {
        _buy(alice, usdcAmount);
    }

    /// Finalize by timestamp and register finalization on vaults.
    function _finalize() internal {
        vm.warp(presaleEnd);
        presale.finalizePresale();
    }

    // ════════════════════════════════════════════════════════════════════════
    // DevRunwayVault
    // ════════════════════════════════════════════════════════════════════════

    function test_Dev_NoWithdrawableAtStart() public {
        _seedVaults(500_000e6);
        // presaleStart == block.timestamp in setUp, stream not yet accumulating
        vm.warp(presaleStart);
        assertEq(devRunwayVault.withdrawableDev(), 0);
    }

    function test_Dev_StreamAccumulatesFromPresaleStart() public {
        _seedVaults(500_000e6);

        // 15% of 500k deposited = 75,000 USDC in dev vault
        uint256 deposited = devRunwayVault.totalDeposited();
        assertEq(deposited, 75_000e6);

        // Advance 45 days (25% of 180-day stream)
        vm.warp(presaleStart + 45 days);

        // streamedDevAmount = DEV_MAX_BUDGET * 45/180 = 1,050,000 * 0.25 = 262,500 USDC
        // but cap is deposited (75,000), so withdrawable = 75,000
        uint256 withdrawable = devRunwayVault.withdrawableDev();
        assertEq(withdrawable, deposited); // stream already covers full deposit
    }

    function test_Dev_WithdrawableCapsByDeposited() public {
        // Buy a small amount so deposited < full stream
        _seedVaults(10_000e6); // 15% = 1,500 USDC deposited

        vm.warp(presaleStart + 90 days); // 50% stream = 525,000 USDC >> 1,500

        // withdrawable must be capped to deposited, not the stream amount
        assertEq(devRunwayVault.withdrawableDev(), devRunwayVault.totalDeposited());
    }

    function test_Dev_PartialWithdrawReducesNext() public {
        _seedVaults(500_000e6); // 75,000 USDC in dev vault
        vm.warp(presaleStart + 90 days); // stream covers full deposit

        uint256 first = 20_000e6;
        vm.prank(devOperator);
        devRunwayVault.withdraw(first);

        assertEq(devRunwayVault.totalWithdrawn(), first);
        assertEq(devRunwayVault.withdrawableDev(), devRunwayVault.totalDeposited() - first);
        assertEq(usdc.balanceOf(devBeneficiary), first);
    }

    function test_Dev_FullWithdrawAfterStreamMatures() public {
        _seedVaults(500_000e6); // 75,000 USDC
        vm.warp(presaleStart + 180 days); // stream fully matured

        uint256 deposited = devRunwayVault.totalDeposited();
        vm.prank(devOperator);
        devRunwayVault.withdraw(deposited);

        assertEq(usdc.balanceOf(devBeneficiary), deposited);
        assertEq(devRunwayVault.withdrawableDev(), 0);
    }

    function test_Dev_FundsGoToBeneficiaryNotCaller() public {
        _seedVaults(100_000e6);
        vm.warp(presaleStart + 90 days);

        vm.prank(devOperator);
        devRunwayVault.withdraw(5_000e6);

        assertEq(usdc.balanceOf(devBeneficiary), 5_000e6);
        assertEq(usdc.balanceOf(devOperator), 0);
    }

    function test_Dev_RevertsWithoutRole() public {
        _seedVaults(100_000e6);
        vm.warp(presaleStart + 90 days);

        vm.prank(alice);
        vm.expectRevert(); // AccessControl revert
        devRunwayVault.withdraw(1_000e6);
    }

    function test_Dev_RevertsOverWithdrawable() public {
        _seedVaults(10_000e6); // 1,500 USDC deposited
        vm.warp(presaleStart + 90 days);

        uint256 deposited = devRunwayVault.totalDeposited();
        vm.prank(devOperator);
        vm.expectRevert(WithdrawalExceedsLimit.selector);
        devRunwayVault.withdraw(deposited + 1);
    }

    function test_Dev_RevertsZeroAmount() public {
        _seedVaults(100_000e6);
        vm.warp(presaleStart + 90 days);

        vm.prank(devOperator);
        vm.expectRevert(ZeroAmount.selector);
        devRunwayVault.withdraw(0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // TeamStreamVault
    // ════════════════════════════════════════════════════════════════════════

    function test_Team_NoWithdrawableAtStreamStart() public {
        _seedVaults(500_000e6);
        vm.warp(presaleStart);
        assertEq(teamStreamVault.withdrawableAmount(), 0);
    }

    function test_Team_StreamIsProportionalToDeposited() public {
        _seedVaults(500_000e6); // 10% = 50,000 USDC in team vault

        // Advance to 50% of 365-day stream
        vm.warp(presaleStart + 182 days);

        uint256 deposited = teamStreamVault.totalDeposited(); // 50,000e6
        uint256 expected = (deposited * 182 days) / 365 days;
        assertApproxEqAbs(teamStreamVault.withdrawableAmount(), expected, 1e3);
    }

    function test_Team_FullDepositWithdrawableAfterStreamEnd() public {
        _seedVaults(500_000e6); // 50,000 USDC deposited

        vm.warp(presaleStart + 365 days);

        uint256 deposited = teamStreamVault.totalDeposited();
        assertEq(teamStreamVault.withdrawableAmount(), deposited);

        vm.prank(teamOperator);
        teamStreamVault.withdraw(deposited);

        assertEq(usdc.balanceOf(teamBeneficiary), deposited);
        assertEq(teamStreamVault.withdrawableAmount(), 0);
    }

    function test_Team_MultiplePartialWithdrawals() public {
        _seedVaults(500_000e6); // 50,000 USDC

        vm.warp(presaleStart + 365 days); // fully streamed

        uint256 deposited = teamStreamVault.totalDeposited();

        vm.prank(teamOperator);
        teamStreamVault.withdraw(10_000e6);
        vm.prank(teamOperator);
        teamStreamVault.withdraw(10_000e6);

        assertEq(teamStreamVault.totalWithdrawn(), 20_000e6);
        assertEq(teamStreamVault.withdrawableAmount(), deposited - 20_000e6);
        assertEq(usdc.balanceOf(teamBeneficiary), 20_000e6);
    }

    function test_Team_FundsGoToBeneficiary() public {
        _seedVaults(100_000e6);
        vm.warp(presaleStart + 365 days);

        vm.prank(teamOperator);
        teamStreamVault.withdraw(5_000e6);

        assertEq(usdc.balanceOf(teamBeneficiary), 5_000e6);
        assertEq(usdc.balanceOf(teamOperator), 0);
    }

    function test_Team_RevertsWithoutRole() public {
        _seedVaults(100_000e6);
        vm.warp(presaleStart + 365 days);

        vm.prank(alice);
        vm.expectRevert();
        teamStreamVault.withdraw(1_000e6);
    }

    function test_Team_RevertsOverWithdrawable() public {
        _seedVaults(100_000e6);
        vm.warp(presaleStart + 365 days);

        uint256 deposited = teamStreamVault.totalDeposited();
        vm.prank(teamOperator);
        vm.expectRevert(WithdrawalExceedsLimit.selector);
        teamStreamVault.withdraw(deposited + 1);
    }

    // ════════════════════════════════════════════════════════════════════════
    // MarketingVault
    // ════════════════════════════════════════════════════════════════════════

    function test_Marketing_LockedBeforeFinalization() public {
        _seedVaults(500_000e6); // 5% = 25,000 USDC deposited

        vm.prank(marketingOperator);
        vm.expectRevert(MarketingLocked.selector);
        marketingVault.queueWithdrawal(1_000e6);
    }

    function test_Marketing_QueueAndExecuteAfterFinalization() public {
        _seedVaults(500_000e6);
        _finalize(); // presaleFinalized == true

        uint256 deposited = marketingVault.totalDeposited();

        // Queue
        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(deposited);

        assertEq(marketingVault.pendingWithdrawalAmount(), deposited);

        // Try to execute before timelock (2 days)
        vm.prank(marketingOperator);
        vm.expectRevert(TimelockNotReady.selector);
        marketingVault.executeWithdrawal();

        // Advance past timelock
        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(marketingOperator);
        marketingVault.executeWithdrawal();

        assertEq(usdc.balanceOf(marketingBeneficiary), deposited);
        assertEq(marketingVault.availableBalance(), 0);
    }

    function test_Marketing_CancelAndRequeue() public {
        _seedVaults(500_000e6);
        _finalize();

        uint256 deposited = marketingVault.totalDeposited();

        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(deposited);

        // Cancel
        vm.prank(marketingOperator);
        marketingVault.cancelQueuedWithdrawal();

        assertEq(marketingVault.pendingWithdrawalAmount(), 0);

        // Requeue smaller amount
        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(5_000e6);

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(marketingOperator);
        marketingVault.executeWithdrawal();

        assertEq(usdc.balanceOf(marketingBeneficiary), 5_000e6);
    }

    function test_Marketing_CannotQueueTwice() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(1_000e6);

        vm.prank(marketingOperator);
        vm.expectRevert(InvalidConfiguration.selector);
        marketingVault.queueWithdrawal(1_000e6);
    }

    function test_Marketing_CannotExecuteWithoutQueue() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.prank(marketingOperator);
        vm.expectRevert(NoQueuedWithdrawal.selector);
        marketingVault.executeWithdrawal();
    }

    function test_Marketing_RevertsWithoutRole() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.prank(alice);
        vm.expectRevert();
        marketingVault.queueWithdrawal(1_000e6);
    }

    function test_Marketing_FundsGoToBeneficiary() public {
        _seedVaults(100_000e6);
        _finalize();

        uint256 deposited = marketingVault.totalDeposited();

        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(deposited);

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(marketingOperator);
        marketingVault.executeWithdrawal();

        assertEq(usdc.balanceOf(marketingBeneficiary), deposited);
        assertEq(usdc.balanceOf(marketingOperator), 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // LiquidityVault
    // ════════════════════════════════════════════════════════════════════════

    function test_Liquidity_PrimaryPathSucceedsWithinWindow() public {
        _seedVaults(500_000e6);
        _finalize();

        uint256 deposited = liquidityVault.totalDeposited();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        assertTrue(liquidityVault.liquidityProvisioned());
        assertEq(usdc.balanceOf(liquidityRecipient), deposited);
    }

    function test_Liquidity_PrimaryPathRevertsWithoutRole() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.prank(alice);
        vm.expectRevert();
        liquidityVault.provideLiquidity();
    }

    function test_Liquidity_PrimaryPathRevertsBeforeFinalization() public {
        _seedVaults(500_000e6);

        vm.prank(liquidityOperator);
        vm.expectRevert(PresaleNotFinalized.selector);
        liquidityVault.provideLiquidity();
    }

    function test_Liquidity_PrimaryPathRevertsAfterWindow() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(liquidityOperator);
        vm.expectRevert(LiquidityWindowExpired.selector);
        liquidityVault.provideLiquidity();
    }

    function test_Liquidity_FallbackPathSucceedsAfterWindow() public {
        _seedVaults(500_000e6);
        _finalize();

        // Wait past the 7-day operator window
        vm.warp(block.timestamp + 7 days + 1);

        uint256 deposited = liquidityVault.totalDeposited();

        vm.prank(alice); // anyone can call fallback
        liquidityVault.provideLiquidityFallback();

        assertTrue(liquidityVault.liquidityProvisioned());
        assertEq(usdc.balanceOf(liquidityRecipient), deposited);
    }

    function test_Liquidity_FallbackRevertsBeforeWindow() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        vm.expectRevert(LiquidityFallbackNotAvailable.selector);
        liquidityVault.provideLiquidityFallback();
    }

    function test_Liquidity_CannotProvisionTwice() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        vm.prank(liquidityOperator);
        vm.expectRevert(LiquidityAlreadyProvisioned.selector);
        liquidityVault.provideLiquidity();
    }

    function test_Liquidity_FallbackCannotProvisionTwice() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.warp(block.timestamp + 7 days + 1);

        liquidityVault.provideLiquidityFallback();

        vm.expectRevert(LiquidityAlreadyProvisioned.selector);
        liquidityVault.provideLiquidityFallback();
    }

    function test_Liquidity_FundsGoToRecipientNotCaller() public {
        _seedVaults(500_000e6);
        _finalize();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        assertEq(usdc.balanceOf(liquidityOperator), 0);
        assertTrue(usdc.balanceOf(liquidityRecipient) > 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Routing: buy correctly splits across all vaults
    // ════════════════════════════════════════════════════════════════════════

    function test_Routing_BuySplitsCorrectly() public {
        // $100k fits within phase 1 token cap (50M tokens at $0.010 = $500k max)
        uint256 buyAmount = 100_000e6;
        _seedVaults(buyAmount);

        assertEq(presale.totalRaisedUSDC(), buyAmount);

        // 70/15/10/5 split
        assertEq(liquidityVault.totalDeposited(), (buyAmount * 70) / 100);
        assertEq(devRunwayVault.totalDeposited(), (buyAmount * 15) / 100);
        assertEq(teamStreamVault.totalDeposited(), (buyAmount * 10) / 100);
        assertEq(marketingVault.totalDeposited(), (buyAmount * 5) / 100);
    }

    // ════════════════════════════════════════════════════════════════════════
    // End-to-end: full presale lifecycle with all withdrawals
    // ════════════════════════════════════════════════════════════════════════

    function test_E2E_FullLifecycle() public {
        // 1. Seed sales across phases using the base helper ($6M across 6 phases)
        _fillToPhase6();

        // 2. Dev and team can start withdrawing as stream accrues
        vm.warp(presaleStart + 90 days);

        uint256 devWithdrawable = devRunwayVault.withdrawableDev();
        assertTrue(devWithdrawable > 0);

        vm.prank(devOperator);
        devRunwayVault.withdraw(devWithdrawable);
        assertEq(usdc.balanceOf(devBeneficiary), devWithdrawable);

        uint256 teamWithdrawable = teamStreamVault.withdrawableAmount();
        assertTrue(teamWithdrawable > 0);

        vm.prank(teamOperator);
        teamStreamVault.withdraw(teamWithdrawable);
        assertEq(usdc.balanceOf(teamBeneficiary), teamWithdrawable);

        // 3. Finalize by timestamp
        vm.warp(presaleEnd);
        presale.finalizePresale();

        // 4. Marketing unlocks: queue → wait → execute
        uint256 marketingDeposited = marketingVault.totalDeposited();
        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(marketingDeposited);

        vm.warp(block.timestamp + 2 days + 1);

        vm.prank(marketingOperator);
        marketingVault.executeWithdrawal();
        assertTrue(usdc.balanceOf(marketingBeneficiary) > 0);

        // 5. Liquidity provisioned by operator
        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();
        assertTrue(liquidityVault.liquidityProvisioned());
        assertTrue(usdc.balanceOf(liquidityRecipient) > 0);

        // 6. Claims enabled after liquidity provisioned
        claimModule.enableClaims();
        assertTrue(claimModule.claimsEnabled());
    }
}
