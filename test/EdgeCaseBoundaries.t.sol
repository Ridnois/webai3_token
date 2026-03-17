// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PresaleSystemTestBase } from "./helpers/PresaleSystemTestBase.sol";
import {
    NothingClaimable,
    ClaimsNotEnabled,
    LiquidityWindowExpired,
    LiquidityFallbackNotAvailable,
    ForceUnpauseUnavailable,
    TimelockNotReady,
    PhaseCapExceeded
} from "../src/presale/PresaleErrors.sol";

/// @notice Edge case and exact-boundary tests.
///
/// These tests target the specific timestamp, cap, and state boundaries that unit tests
/// miss by using +1 / -1 offsets. Each test names the exact operator being verified
/// (>, >=, <, <=) so a future reader immediately understands what property is under test.
contract EdgeCaseBoundaryTest is PresaleSystemTestBase {
    // ════════════════════════════════════════════════════════════════════════
    // Phase USDC boundary — getActivePhase() uses strict less-than (<)
    // ════════════════════════════════════════════════════════════════════════

    /// Phase 0→1: totalRaisedUSDC reaches exactly 500k.
    /// getActivePhase uses `totalRaisedUSDC < cap` — at equality the phase advances.
    function test_PhaseBoundary_500k_AdvancesToPhase1() public {
        assertEq(presale.getActivePhase(), 0);
        _buy(alice, 500_000e6);
        assertEq(presale.totalRaisedUSDC(), 500_000e6);
        assertEq(presale.getActivePhase(), 1);
    }

    /// Phase 1→2: totalRaisedUSDC reaches exactly 1M.
    function test_PhaseBoundary_1M_AdvancesToPhase2() public {
        _buy(alice, 500_000e6); // end phase 0
        assertEq(presale.getActivePhase(), 1);

        _buy(bob, 500_000e6); // fills phase 1 exactly to its USDC cap
        assertEq(presale.totalRaisedUSDC(), 1_000_000e6);
        assertEq(presale.getActivePhase(), 2);
    }

    /// Phase 2→3: totalRaisedUSDC reaches exactly 2M.
    function test_PhaseBoundary_2M_AdvancesToPhase3() public {
        _buy(alice, 500_000e6);
        _buy(bob, 500_000e6);
        assertEq(presale.getActivePhase(), 2);

        _buy(carol, 1_000_000e6);
        assertEq(presale.totalRaisedUSDC(), 2_000_000e6);
        assertEq(presale.getActivePhase(), 3);
    }

    /// Phase 3→4: totalRaisedUSDC reaches exactly 3.5M.
    function test_PhaseBoundary_3_5M_AdvancesToPhase4() public {
        _buy(alice, 500_000e6);
        _buy(bob, 500_000e6);
        _buy(carol, 1_000_000e6);
        assertEq(presale.getActivePhase(), 3);

        _buy(dave, 1_500_000e6);
        assertEq(presale.totalRaisedUSDC(), 3_500_000e6);
        assertEq(presale.getActivePhase(), 4);
    }

    /// Phase 4→5: totalRaisedUSDC reaches exactly 5M.
    function test_PhaseBoundary_5M_AdvancesToPhase5() public {
        _buy(alice, 500_000e6);
        _buy(bob, 500_000e6);
        _buy(carol, 1_000_000e6);
        _buy(dave, 1_500_000e6);
        assertEq(presale.getActivePhase(), 4);

        _buy(alice, 1_500_000e6);
        assertEq(presale.totalRaisedUSDC(), 5_000_000e6);
        assertEq(presale.getActivePhase(), 5);
    }

    /// Phase 5→6: totalRaisedUSDC reaches exactly 6M.
    function test_PhaseBoundary_6M_AdvancesToPhase6() public {
        _buy(alice, 500_000e6);
        _buy(bob, 500_000e6);
        _buy(carol, 1_000_000e6);
        _buy(dave, 1_500_000e6);
        _buy(alice, 1_500_000e6);
        assertEq(presale.getActivePhase(), 5);

        _buy(bob, 1_000_000e6);
        assertEq(presale.totalRaisedUSDC(), 6_000_000e6);
        assertEq(presale.getActivePhase(), 6);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Phase token cap exact boundary — PhaseCapExceeded uses strict greater-than (>)
    // ════════════════════════════════════════════════════════════════════════

    /// Fill phase 0 to exactly its token cap in two purchases:
    ///   - first buy leaves exactly 1,000 AIC of remaining capacity
    ///   - second buy fills exactly 1,000 AIC → soldTokens == tokenCap
    /// The check `soldTokens + aicAmount > tokenCap` uses `>`, so equality passes.
    ///
    /// Phase 0 price: pricePerTokenUSDC6 = 10_000
    /// aicAmount = (usdcAmount * 1e18) / 10_000
    /// For 1,000 AIC: usdcAmount = 1_000 * 10_000 = 10_000_000 USDC6 (= 10 USDC)
    function test_PhaseTokenCap_ExactFill_Phase0() public {
        // Phase 0: tokenCap = 50,000,000 AIC, pricePerTokenUSDC6 = 10,000
        // Buy 49,999,000 AIC → leaves 1,000 AIC of capacity
        //   usdcAmount = 49_999_000 * 10_000 = 499_990_000_000 USDC6 = 499_990e6
        uint256 firstBuy = _buy(alice, 499_990e6);
        assertEq(firstBuy, 49_999_000 ether);

        // Remaining capacity: exactly 1,000 AIC
        (, , uint256 tokenCap,, uint256 remaining) = presale.getPhaseInfo(0);
        assertEq(remaining, 1_000 ether);

        // Fill the last 1,000 AIC: usdcAmount = 1_000 * 10_000 = 10_000_000 USDC6 (= 10 USDC)
        uint256 lastBuy = _buy(bob, 10_000_000);
        assertEq(lastBuy, 1_000 ether);

        // soldTokens must now equal tokenCap exactly
        (, , , uint256 soldTokens,) = presale.getPhaseInfo(0);
        assertEq(soldTokens, tokenCap);

        // Phase must have advanced
        assertEq(presale.getActivePhase(), 1);
    }

    /// Buying one token beyond the remaining phase 0 capacity reverts with PhaseCapExceeded.
    function test_PhaseTokenCap_OneBeyond_Reverts() public {
        // Fill phase 0 to leave 1,000 AIC remaining
        _buy(alice, 499_990e6);

        // Try to buy 1,001 AIC (1 beyond the 1,000 remaining) → PhaseCapExceeded
        //   usdcAmount = 1_001 * 10_000 = 10_010_000 USDC6 (= 10.01 USDC)
        _fundAndApprove(bob, 10_010_000);
        vm.prank(bob);
        vm.expectRevert(PhaseCapExceeded.selector);
        presale.buyTokens(10_010_000);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Allocation cap boundary — check uses strict greater-than (>)
    // ════════════════════════════════════════════════════════════════════════

    /// Filling the entire hard cap (7M USDC) must never trigger AllocationCapExceeded.
    /// Both WebAI3Presale and ClaimModule use `newTotal > PRESALE_TOKEN_CAP`, meaning
    /// a total of exactly 500M tokens is allowed.
    function test_AllocationCap_FullPresaleFill_NeverExceeds() public {
        // _fillHardCap buys all 7M USDC across all 7 phases
        _fillHardCap();

        uint256 totalAllocated = presale.totalAllocatedTokens();
        uint256 totalRecorded = claimModule.totalRecordedAllocations();
        uint256 cap = presale.PRESALE_TOKEN_CAP();

        // Must not exceed the cap (rounding-down purchases always stay at or below)
        assertTrue(totalAllocated <= cap, "presale.totalAllocatedTokens exceeded cap");
        assertTrue(totalRecorded <= cap, "claimModule.totalRecordedAllocations exceeded cap");

        // Both trackers must agree
        assertEq(totalAllocated, totalRecorded);
    }

    // ════════════════════════════════════════════════════════════════════════
    // LiquidityVault window — exact 7-day boundary
    // provideLiquidity uses `>` (expired after), provideLiquidityFallback uses `<=` (available after)
    // ════════════════════════════════════════════════════════════════════════

    /// At exactly finalizedAt + 7 days, the operator window has NOT expired.
    /// Condition: `block.timestamp > finalizedAt + MAX_LIQUIDITY_DELAY` — false at equality.
    function test_Liquidity_PrimaryPath_AtExactly7Days_Succeeds() public {
        _buy(alice, 100_000e6);
        uint256 finalizedAt_ = _finalizeAndGetTimestamp();

        vm.warp(finalizedAt_ + 7 days); // exactly at the boundary

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity(); // must NOT revert

        assertTrue(liquidityVault.liquidityProvisioned());
    }

    /// At exactly finalizedAt + 7 days, the fallback is NOT yet available.
    /// Condition: `block.timestamp <= finalizedAt + MAX_LIQUIDITY_DELAY` — true at equality → revert.
    function test_Liquidity_FallbackPath_AtExactly7Days_Reverts() public {
        _buy(alice, 100_000e6);
        uint256 finalizedAt_ = _finalizeAndGetTimestamp();

        vm.warp(finalizedAt_ + 7 days); // exactly at the boundary

        vm.expectRevert(LiquidityFallbackNotAvailable.selector);
        liquidityVault.provideLiquidityFallback(); // must revert
    }

    /// One second after 7 days: primary path expires, fallback becomes available.
    function test_Liquidity_OneSecondAfter7Days_PrimaryExpires_FallbackAvailable() public {
        _buy(alice, 100_000e6);
        uint256 finalizedAt_ = _finalizeAndGetTimestamp();

        vm.warp(finalizedAt_ + 7 days + 1);

        // Primary path now expired
        vm.prank(liquidityOperator);
        vm.expectRevert(LiquidityWindowExpired.selector);
        liquidityVault.provideLiquidity();

        // Fallback now available
        vm.prank(bob);
        liquidityVault.provideLiquidityFallback();
        assertTrue(liquidityVault.liquidityProvisioned());
    }

    // ════════════════════════════════════════════════════════════════════════
    // forceUnpause — exact 72-hour boundary
    // Condition: `block.timestamp < pauseStartedAt + MAX_SINGLE_PAUSE` → revert if true
    // At equality (exactly 72h): condition is false → forceUnpause succeeds
    // ════════════════════════════════════════════════════════════════════════

    /// At exactly 72 hours from pause start, forceUnpause must succeed.
    /// Existing tests only check 70h (fails) and 73h (succeeds); this closes the gap.
    function test_ForceUnpause_AtExactly72Hours_Succeeds() public {
        uint256 pausedAt = block.timestamp;

        vm.prank(pauser);
        presale.pause();

        vm.warp(pausedAt + 72 hours); // exactly at MAX_SINGLE_PAUSE

        presale.forceUnpause(); // must NOT revert

        assertFalse(presale.pauseActive());
    }

    /// One second before 72h: forceUnpause must still revert.
    function test_ForceUnpause_OneSecondBefore72Hours_Reverts() public {
        uint256 pausedAt = block.timestamp;

        vm.prank(pauser);
        presale.pause();

        vm.warp(pausedAt + 72 hours - 1);

        vm.expectRevert(ForceUnpauseUnavailable.selector);
        presale.forceUnpause();
    }

    // ════════════════════════════════════════════════════════════════════════
    // MarketingVault timelock — exact 2-day boundary
    // Condition: `block.timestamp < pendingWithdrawalReadyAt` → revert if true
    // At equality (exactly readyAt): condition is false → executeWithdrawal succeeds
    // ════════════════════════════════════════════════════════════════════════

    /// executeWithdrawal called at exactly pendingWithdrawalReadyAt must succeed.
    /// Existing tests use +2 days + 1; this tests the exact boundary.
    function test_Marketing_Execute_AtExactTimelock_Succeeds() public {
        _buy(alice, 200_000e6);
        _finalizeByTimestamp();

        uint256 queuedAt = block.timestamp;
        uint256 amount = marketingVault.availableBalance();

        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(amount);

        uint256 readyAt = queuedAt + 2 days; // withdrawalDelay is 2 days in setUp
        vm.warp(readyAt); // exactly at the timelock expiry

        vm.prank(marketingOperator);
        marketingVault.executeWithdrawal(); // must NOT revert

        assertEq(usdc.balanceOf(marketingBeneficiary), amount);
    }

    /// One second before the timelock: executeWithdrawal must still revert.
    function test_Marketing_Execute_OneSecondBeforeTimelock_Reverts() public {
        _buy(alice, 200_000e6);
        _finalizeByTimestamp();

        uint256 queuedAt = block.timestamp;
        uint256 amount = marketingVault.availableBalance();

        vm.prank(marketingOperator);
        marketingVault.queueWithdrawal(amount);

        vm.warp(queuedAt + 2 days - 1);

        vm.prank(marketingOperator);
        vm.expectRevert(TimelockNotReady.selector);
        marketingVault.executeWithdrawal();
    }

    // ════════════════════════════════════════════════════════════════════════
    // ClaimModule — double-claim and zero-allocation
    // ════════════════════════════════════════════════════════════════════════

    /// A buyer who claims their full TGE tranche (30%) and immediately calls claim()
    /// again before the next vesting checkpoint must get NothingClaimable.
    function test_Claim_DoubleClaim_AfterTGE_Reverts() public {
        _buy(alice, 1_000e6); // 100,000 AIC allocation

        _finalizeByTimestamp();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        claimModule.enableClaims();

        vm.warp(tge);

        // First claim at TGE: receives 30%
        vm.prank(alice);
        claimModule.claim();
        assertEq(aic.balanceOf(alice), 30_000 ether);

        // Immediately re-claim at same timestamp: nothing new has vested
        vm.prank(alice);
        vm.expectRevert(NothingClaimable.selector);
        claimModule.claim();
    }

    /// A buyer who claims at TGE, waits until TGE + 1 second (still in 30% tranche),
    /// and tries to claim again must get NothingClaimable.
    function test_Claim_DoubleClaim_BeforeNextTranche_Reverts() public {
        _buy(alice, 1_000e6);

        _finalizeByTimestamp();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        claimModule.enableClaims();

        vm.warp(tge);

        vm.prank(alice);
        claimModule.claim(); // 30% claimed

        vm.warp(tge + 1); // 1 second later, still in 30% tranche

        vm.prank(alice);
        vm.expectRevert(NothingClaimable.selector);
        claimModule.claim();
    }

    /// A wallet that never participated in the presale has zero allocation.
    /// Calling claim() must revert with NothingClaimable (not ClaimsNotEnabled or similar).
    function test_Claim_ZeroAllocation_Reverts() public {
        _buy(alice, 1_000e6); // alice participates; dave never does

        _finalizeByTimestamp();

        vm.prank(liquidityOperator);
        liquidityVault.provideLiquidity();

        claimModule.enableClaims();

        vm.warp(tge);

        assertEq(claimModule.totalAllocation(dave), 0);

        vm.prank(dave);
        vm.expectRevert(NothingClaimable.selector);
        claimModule.claim();
    }

    /// claimableAmount() returns zero for a zero-allocation address (view function, no revert).
    function test_ClaimableAmount_ZeroAllocation_ReturnsZero() public view {
        assertEq(claimModule.claimableAmount(dave), 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Internal helpers
    // ════════════════════════════════════════════════════════════════════════

    /// Finalize by timestamp and return the exact block.timestamp at finalization.
    function _finalizeAndGetTimestamp() internal returns (uint256 finalizedAt_) {
        vm.warp(presaleEnd);
        presale.finalizePresale();
        finalizedAt_ = block.timestamp;
    }
}
