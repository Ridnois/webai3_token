// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { WebAI3Presale } from "../src/WebAI3Presale.sol";

// ──────────────────────────────────────────────────
// Mock ERC-20 tokens for testing
// ──────────────────────────────────────────────────

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAIC is ERC20 {
    constructor() ERC20("WebAI3 Token", "AIC") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ──────────────────────────────────────────────────
// Test contract
// ──────────────────────────────────────────────────

contract WebAI3PresaleTest is Test {
    MockUSDC internal usdc;
    MockAIC internal aic;
    WebAI3Presale internal presale;

    address internal owner = makeAddr("owner");
    address internal treasuryAddr = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // Phase configuration matching PRESALE_ARCHITECTURE.md
    // Phase 1: $0–$500k,   $0.010, 50M AIC,   14 days
    // Phase 2: $500k–$1M,  $0.013, 38.5M AIC, 14 days
    // Phase 3: $1M–$2M,    $0.020, 50M AIC,   14 days
    // Phase 4: $2M–$3.5M,  $0.028, 53.6M AIC, 21 days
    // Phase 5: $3.5M–$5M,  $0.038, 39.5M AIC, 21 days
    // Phase 6: $5M–$6M,    $0.053, 18.9M AIC, 21 days
    // Phase 7: $6M–$7M,    $0.070, 250M AIC,  35 days

    uint256 internal constant PHASE_COUNT = 7;

    uint256[7] internal phaseCaps =
        [500_000e6, 1_000_000e6, 2_000_000e6, 3_500_000e6, 5_000_000e6, 6_000_000e6, 7_000_000e6];
    uint256[7] internal phasePrices = [0.01e6, 0.013e6, 0.02e6, 0.028e6, 0.038e6, 0.053e6, 0.07e6];
    uint256[7] internal phaseMaxTokens = [
        50_000_000 ether,
        38_500_000 ether,
        50_000_000 ether,
        53_600_000 ether,
        39_500_000 ether,
        18_900_000 ether,
        250_000_000 ether
    ];
    uint256[7] internal phaseDurations =
        [14 days, 14 days, 14 days, 21 days, 21 days, 21 days, 35 days];

    // ──────────────────────────────────────────────
    // Setup
    // ──────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        aic = new MockAIC();
        presale = new WebAI3Presale(address(usdc), address(aic), treasuryAddr);
        vm.stopPrank();

        // Fund presale with AIC tokens for claims
        aic.mint(address(presale), 500_000_000 ether);
    }

    function _buildPhases() internal view returns (WebAI3Presale.Phase[] memory phases) {
        phases = new WebAI3Presale.Phase[](PHASE_COUNT);
        uint256 start = block.timestamp;
        for (uint256 i = 0; i < PHASE_COUNT; i++) {
            uint256 end = start + phaseDurations[i];
            phases[i] = WebAI3Presale.Phase({
                phaseCap: phaseCaps[i],
                pricePerToken: phasePrices[i],
                maxTokens: phaseMaxTokens[i],
                startTime: start,
                endTime: end,
                soldTokens: 0
            });
            start = end;
        }
    }

    function _initPresale() internal {
        vm.prank(owner);
        presale.initializePresale(_buildPhases());
    }

    /// @dev Fund a user with USDC, approve presale, and return the amount.
    function _fundAndApprove(address user, uint256 usdcAmount) internal {
        usdc.mint(user, usdcAmount);
        vm.prank(user);
        usdc.approve(address(presale), usdcAmount);
    }

    /// @dev Buy tokens as a specific user.
    function _buy(address user, uint256 usdcAmount) internal returns (uint256 aicAmount) {
        _fundAndApprove(user, usdcAmount);
        vm.prank(user);
        aicAmount = presale.buyTokens(usdcAmount);
    }

    // ════════════════════════════════════════════════
    //  1. CONSTRUCTOR & INITIALIZATION
    // ════════════════════════════════════════════════

    function test_ConstructorSetsImmutables() public view {
        assertEq(address(presale.usdc()), address(usdc));
        assertEq(address(presale.aicToken()), address(aic));
        assertEq(presale.treasury(), treasuryAddr);
        assertEq(presale.owner(), owner);
    }

    function test_ConstructorRevertsOnZeroUsdc() public {
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidAddress.selector);
        new WebAI3Presale(address(0), address(aic), treasuryAddr);
    }

    function test_ConstructorRevertsOnZeroAic() public {
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidAddress.selector);
        new WebAI3Presale(address(usdc), address(0), treasuryAddr);
    }

    function test_ConstructorRevertsOnZeroTreasury() public {
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidAddress.selector);
        new WebAI3Presale(address(usdc), address(aic), address(0));
    }

    function test_InitializePresale() public {
        _initPresale();
        assertEq(presale.getPhaseCount(), PHASE_COUNT);
        assertTrue(presale.presaleActive());

        // Verify each phase was stored correctly
        for (uint256 i = 0; i < PHASE_COUNT; i++) {
            WebAI3Presale.Phase memory p = presale.getPhaseInfo(i);
            assertEq(p.phaseCap, phaseCaps[i]);
            assertEq(p.pricePerToken, phasePrices[i]);
            assertEq(p.maxTokens, phaseMaxTokens[i]);
            assertEq(p.soldTokens, 0);
        }
    }

    function test_InitializeSetsTgeTime() public {
        _initPresale();
        WebAI3Presale.Phase memory lastPhase = presale.getPhaseInfo(PHASE_COUNT - 1);
        assertEq(presale.tgeTime(), lastPhase.endTime + 7 days);
    }

    function test_InitializeRevertsIfAlreadyInitialized() public {
        _initPresale();
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.PresaleAlreadyInitialized.selector);
        presale.initializePresale(_buildPhases());
    }

    function test_InitializeRevertsOnEmptyPhases() public {
        WebAI3Presale.Phase[] memory empty = new WebAI3Presale.Phase[](0);
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidPhaseConfig.selector);
        presale.initializePresale(empty);
    }

    function test_InitializeRevertsOnNonZeroSoldTokens() public {
        WebAI3Presale.Phase[] memory phases = _buildPhases();
        phases[0].soldTokens = 1;
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidPhaseConfig.selector);
        presale.initializePresale(phases);
    }

    function test_InitializeRevertsOnZeroPrice() public {
        WebAI3Presale.Phase[] memory phases = _buildPhases();
        phases[0].pricePerToken = 0;
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidPhaseConfig.selector);
        presale.initializePresale(phases);
    }

    function test_InitializeRevertsOnUnorderedCaps() public {
        WebAI3Presale.Phase[] memory phases = _buildPhases();
        phases[1].phaseCap = phases[0].phaseCap; // Equal, not ascending
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.PhasesNotOrdered.selector);
        presale.initializePresale(phases);
    }

    function test_InitializeRevertsOnInvertedTimes() public {
        WebAI3Presale.Phase[] memory phases = _buildPhases();
        phases[0].endTime = phases[0].startTime; // startTime == endTime
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.InvalidPhaseConfig.selector);
        presale.initializePresale(phases);
    }

    function test_OnlyOwnerCanInitialize() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        presale.initializePresale(_buildPhases());
    }

    // ════════════════════════════════════════════════
    //  2. PHASE LOGIC — getActivePhase
    // ════════════════════════════════════════════════

    function test_ActivePhaseIsZeroOnInit() public {
        _initPresale();
        assertEq(presale.getActivePhase(), 0);
    }

    function test_ActivePhaseReturnsMaxIfNotStarted() public {
        // Build phases that start in the future
        WebAI3Presale.Phase[] memory phases = new WebAI3Presale.Phase[](1);
        phases[0] = WebAI3Presale.Phase({
            phaseCap: 100e6,
            pricePerToken: 0.01e6,
            maxTokens: 100 ether,
            startTime: block.timestamp + 100,
            endTime: block.timestamp + 200,
            soldTokens: 0
        });
        vm.prank(owner);
        presale.initializePresale(phases);

        assertEq(presale.getActivePhase(), type(uint256).max);
    }

    function test_ActivePhaseAdvancesWhenCapMet() public {
        _initPresale();

        // Fill Phase 1 exactly ($500k at $0.01 = 50M AIC = Phase 1 max)
        _buy(alice, 500_000e6);
        // Phase 1 cap met — getActivePhase should now return 1 (fund-driven advance)
        assertEq(presale.getActivePhase(), 1);
    }

    function test_ActivePhaseSkipsFilledPhases() public {
        _initPresale();

        // Fill Phase 1 ($500k)
        _buy(alice, 500_000e6);
        // Fill Phase 2 ($500k more at $0.013 — within 38.5M token cap)
        _buy(bob, 500_000e6);
        // totalRaised = $1M = Phase 2 cap, so active = Phase 2 (index 2)
        assertEq(presale.getActivePhase(), 2);
    }

    function test_ActivePhaseReturnsMaxAfterAllPhasesExpired() public {
        _initPresale();
        // Warp past all phases
        WebAI3Presale.Phase memory lastPhase = presale.getPhaseInfo(PHASE_COUNT - 1);
        vm.warp(lastPhase.endTime);
        assertEq(presale.getActivePhase(), type(uint256).max);
    }

    // ════════════════════════════════════════════════
    //  3. BUY TOKENS — Phase 1
    // ════════════════════════════════════════════════

    function test_BuyPhase1CalculatesCorrectTokens() public {
        _initPresale();

        // 1000 USDC at $0.01/token = 100,000 AIC
        uint256 aicAmount = _buy(alice, 1_000e6);
        assertEq(aicAmount, 100_000 ether);
    }

    function test_BuyPhase1UpdatesState() public {
        _initPresale();

        uint256 usdcAmt = 10_000e6; // $10k
        _buy(alice, usdcAmt);

        assertEq(presale.contributions(alice), usdcAmt);
        assertEq(presale.tokenAllocations(alice), (usdcAmt * 1e18) / 0.01e6);
        assertEq(presale.totalRaisedUSDC(), usdcAmt);
        assertEq(presale.totalTokensSold(), (usdcAmt * 1e18) / 0.01e6);
    }

    function test_BuyPhase1TransfersUsdcToContract() public {
        _initPresale();

        uint256 amount = 5_000e6;
        _fundAndApprove(alice, amount);

        uint256 balBefore = usdc.balanceOf(address(presale));
        vm.prank(alice);
        presale.buyTokens(amount);

        assertEq(usdc.balanceOf(address(presale)), balBefore + amount);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_BuyMultiplePurchasesSameUser() public {
        _initPresale();

        _buy(alice, 1_000e6);
        _buy(alice, 2_000e6);

        assertEq(presale.contributions(alice), 3_000e6);
        uint256 expectedAic = (3_000e6 * 1e18) / 0.01e6;
        assertEq(presale.tokenAllocations(alice), expectedAic);
    }

    // ════════════════════════════════════════════════
    //  4. BUY TOKENS — Phase Transitions
    // ════════════════════════════════════════════════

    function test_BuyTriggersPhaseAdvancedEvent() public {
        _initPresale();

        _fundAndApprove(alice, 500_000e6);

        vm.expectEmit(true, false, false, true);
        emit WebAI3Presale.PhaseAdvanced(1, phasePrices[1]);

        vm.prank(alice);
        presale.buyTokens(500_000e6);
    }

    function test_Phase2PriceAppliedAfterPhase1Cap() public {
        _initPresale();

        // Fill Phase 1 ($500k)
        _buy(alice, 500_000e6);
        assertEq(presale.getActivePhase(), 1);

        // Buy in Phase 2 at $0.013 (auto-advanced by funding)
        uint256 aicAmount = _buy(bob, 1_000e6);
        uint256 expected = (uint256(1_000e6) * 1e18) / 13_000;
        assertEq(aicAmount, expected);
    }

    function test_Phase3PriceAfterPhase2Cap() public {
        _initPresale();

        // Fill Phase 1
        _buy(alice, 500_000e6);
        // Fill Phase 2 ($500k at $0.013)
        _buy(alice, 500_000e6);
        assertEq(presale.getActivePhase(), 2);

        // Buy in Phase 3 at $0.020
        uint256 aicAmount = _buy(bob, 1_000e6);
        uint256 expected = (uint256(1_000e6) * 1e18) / 20_000;
        assertEq(aicAmount, expected);
    }

    function test_AllSevenPhasePricesApplyCorrectly() public {
        _initPresale();

        // Walk through all 7 phases — fund-driven auto-advance, no time warps needed.

        // Phase 1 ($500k @ $0.010)
        _buy(alice, 500_000e6);
        assertEq(presale.getActivePhase(), 1);

        // Phase 2 ($500k more @ $0.013)
        _buy(alice, 500_000e6);
        assertEq(presale.getActivePhase(), 2);

        // Phase 3 ($1M more @ $0.020)
        _buy(alice, 1_000_000e6);
        assertEq(presale.getActivePhase(), 3);

        // Phase 4 ($1.5M more @ $0.028)
        _buy(alice, 1_500_000e6);
        assertEq(presale.getActivePhase(), 4);

        // Phase 5 ($1.5M more @ $0.038)
        _buy(alice, 1_500_000e6);
        assertEq(presale.getActivePhase(), 5);

        // Phase 6 ($1M more @ $0.053)
        _buy(alice, 1_000_000e6);
        assertEq(presale.getActivePhase(), 6);

        // Phase 7: verify price ($0.070)
        uint256 aicAmount = _buy(bob, 1_000e6);
        uint256 expected = (uint256(1_000e6) * 1e18) / 70_000;
        assertEq(aicAmount, expected);
    }

    // ════════════════════════════════════════════════
    //  5. TOKEN ALLOCATION PER PHASE
    // ════════════════════════════════════════════════

    function test_Phase1MaxTokensCap() public {
        _initPresale();

        // Phase 1 max tokens = 50M AIC. At $0.01 that's $500k USDC.
        // Try buying one token over the cap.
        // 50M tokens requires exactly $500k. Buy $500k first:
        _buy(alice, 500_000e6);

        // Now any more in phase 1 time should fail since cap is met
        // (and we're now in phase 2 by funds)
        // Instead, let's verify soldTokens == maxTokens for phase 1
        WebAI3Presale.Phase memory p = presale.getPhaseInfo(0);
        assertEq(p.soldTokens, 50_000_000 ether);
    }

    function test_PhaseTokenCapExceededReverts() public {
        // Create a single-phase presale with very limited tokens
        WebAI3Presale.Phase[] memory phases = new WebAI3Presale.Phase[](1);
        phases[0] = WebAI3Presale.Phase({
            phaseCap: 1_000_000e6,
            pricePerToken: 0.01e6,
            maxTokens: 100 ether, // Only 100 AIC
            startTime: block.timestamp,
            endTime: block.timestamp + 30 days,
            soldTokens: 0
        });

        vm.prank(owner);
        WebAI3Presale ps = new WebAI3Presale(address(usdc), address(aic), treasuryAddr);
        vm.prank(owner);
        ps.initializePresale(phases);

        // 100 AIC = 100 * 0.01 = $1 USDC at $0.01 price
        // Try to buy $2 worth = 200 AIC → exceeds 100 AIC cap
        usdc.mint(alice, 2e6);
        vm.prank(alice);
        usdc.approve(address(ps), 2e6);

        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.PhaseTokenCapExceeded.selector);
        ps.buyTokens(2e6);
    }

    function test_Phase1TokenAllocationMatchesDoc() public {
        _initPresale();

        // Buy exactly phase 1 worth ($500k @ $0.01 = 50M AIC)
        _buy(alice, 500_000e6);

        WebAI3Presale.Phase memory p = presale.getPhaseInfo(0);
        assertEq(p.soldTokens, 50_000_000 ether, "Phase 1 should allocate exactly 50M AIC");
    }

    function test_Phase2TokenAllocationMatchesDoc() public {
        _initPresale();

        // Fill Phase 1
        _buy(alice, 500_000e6);
        assertEq(presale.getActivePhase(), 1);

        // Phase 2: $500k–$1M, $0.013/token, max 38.5M AIC
        // $500k at $0.013 = 500_000 / 0.013 = ~38,461,538 AIC (within 38.5M cap)
        _buy(bob, 500_000e6);

        WebAI3Presale.Phase memory p = presale.getPhaseInfo(1);
        uint256 expectedTokens = (uint256(500_000e6) * 1e18) / 13_000;
        assertEq(p.soldTokens, expectedTokens);
    }

    // ════════════════════════════════════════════════
    //  6. HARD CAP
    // ════════════════════════════════════════════════

    function test_HardCapEndsPresale() public {
        _initPresale();

        // Buy $7M total across phases — presale should auto-end.
        // We'll do it in one giant buy in Phase 1 time window
        // (token cap might block this, so let's build a custom presale).
        WebAI3Presale.Phase[] memory phases = new WebAI3Presale.Phase[](1);
        phases[0] = WebAI3Presale.Phase({
            phaseCap: 7_000_000e6,
            pricePerToken: 0.01e6,
            maxTokens: 700_000_000 ether, // Enough for $7M
            startTime: block.timestamp,
            endTime: block.timestamp + 90 days,
            soldTokens: 0
        });

        vm.prank(owner);
        WebAI3Presale ps = new WebAI3Presale(address(usdc), address(aic), treasuryAddr);
        vm.prank(owner);
        ps.initializePresale(phases);

        usdc.mint(alice, 7_000_000e6);
        vm.prank(alice);
        usdc.approve(address(ps), 7_000_000e6);

        vm.prank(alice);
        ps.buyTokens(7_000_000e6);

        assertFalse(ps.presaleActive());
        assertEq(ps.totalRaisedUSDC(), 7_000_000e6);
    }

    function test_HardCapExceededReverts() public {
        // Single-phase, high-token-cap presale
        WebAI3Presale.Phase[] memory phases = new WebAI3Presale.Phase[](1);
        phases[0] = WebAI3Presale.Phase({
            phaseCap: 7_000_000e6,
            pricePerToken: 0.01e6,
            maxTokens: 800_000_000 ether,
            startTime: block.timestamp,
            endTime: block.timestamp + 90 days,
            soldTokens: 0
        });

        vm.prank(owner);
        WebAI3Presale ps = new WebAI3Presale(address(usdc), address(aic), treasuryAddr);
        vm.prank(owner);
        ps.initializePresale(phases);

        // Buy exactly $7M
        usdc.mint(alice, 7_000_001e6);
        vm.prank(alice);
        usdc.approve(address(ps), 7_000_001e6);

        vm.prank(alice);
        ps.buyTokens(7_000_000e6);

        // Next buy of $1 should revert (presaleActive is false)
        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.PresaleNotActive.selector);
        ps.buyTokens(1e6);
    }

    function test_HardCapEmitsPresaleEndedEvent() public {
        WebAI3Presale.Phase[] memory phases = new WebAI3Presale.Phase[](1);
        phases[0] = WebAI3Presale.Phase({
            phaseCap: 7_000_000e6,
            pricePerToken: 0.01e6,
            maxTokens: 700_000_000 ether,
            startTime: block.timestamp,
            endTime: block.timestamp + 90 days,
            soldTokens: 0
        });

        vm.prank(owner);
        WebAI3Presale ps = new WebAI3Presale(address(usdc), address(aic), treasuryAddr);
        vm.prank(owner);
        ps.initializePresale(phases);

        usdc.mint(alice, 7_000_000e6);
        vm.prank(alice);
        usdc.approve(address(ps), 7_000_000e6);

        vm.expectEmit(false, false, false, true);
        emit WebAI3Presale.PresaleEnded(7_000_000e6, 700_000_000 ether);

        vm.prank(alice);
        ps.buyTokens(7_000_000e6);
    }

    // ════════════════════════════════════════════════
    //  7. CLAIM TOKENS
    // ════════════════════════════════════════════════

    function test_ClaimAfterFinalization() public {
        _initPresale();

        uint256 aicAmount = _buy(alice, 1_000e6);

        // Finalize
        vm.prank(owner);
        presale.finalizePresale();

        // Warp to TGE
        vm.warp(presale.tgeTime());

        vm.prank(alice);
        uint256 claimed = presale.claimTokens();
        assertEq(claimed, aicAmount);
        assertEq(aic.balanceOf(alice), aicAmount);
        assertTrue(presale.hasClaimed(alice));
    }

    function test_ClaimRevertsBeforeFinalization() public {
        _initPresale();
        _buy(alice, 1_000e6);

        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.PresaleNotFinalized.selector);
        presale.claimTokens();
    }

    function test_ClaimRevertsBeforeTge() public {
        _initPresale();
        _buy(alice, 1_000e6);

        vm.prank(owner);
        presale.finalizePresale();

        // Still before TGE
        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.TGENotReached.selector);
        presale.claimTokens();
    }

    function test_ClaimRevertsIfNothingAllocated() public {
        _initPresale();

        vm.prank(owner);
        presale.finalizePresale();
        vm.warp(presale.tgeTime());

        vm.prank(bob);
        vm.expectRevert(WebAI3Presale.NothingToClaim.selector);
        presale.claimTokens();
    }

    function test_ClaimRevertsOnDoubleClaim() public {
        _initPresale();
        _buy(alice, 1_000e6);

        vm.prank(owner);
        presale.finalizePresale();
        vm.warp(presale.tgeTime());

        vm.prank(alice);
        presale.claimTokens();

        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.AlreadyClaimed.selector);
        presale.claimTokens();
    }

    function test_ClaimTransfersCorrectAmount() public {
        _initPresale();

        // Alice buys twice
        _buy(alice, 1_000e6);
        _buy(alice, 2_000e6);

        uint256 expectedAic = presale.tokenAllocations(alice);

        vm.prank(owner);
        presale.finalizePresale();
        vm.warp(presale.tgeTime());

        vm.prank(alice);
        presale.claimTokens();

        assertEq(aic.balanceOf(alice), expectedAic);
    }

    function test_MultipleUsersClaim() public {
        _initPresale();

        uint256 aliceAic = _buy(alice, 5_000e6);
        uint256 bobAic = _buy(bob, 10_000e6);

        vm.prank(owner);
        presale.finalizePresale();
        vm.warp(presale.tgeTime());

        vm.prank(alice);
        presale.claimTokens();
        vm.prank(bob);
        presale.claimTokens();

        assertEq(aic.balanceOf(alice), aliceAic);
        assertEq(aic.balanceOf(bob), bobAic);
    }

    // ════════════════════════════════════════════════
    //  8. FINALIZE PRESALE
    // ════════════════════════════════════════════════

    function test_FinalizeTransfersUsdcToTreasury() public {
        _initPresale();
        _buy(alice, 50_000e6);

        uint256 contractBal = usdc.balanceOf(address(presale));
        assertEq(contractBal, 50_000e6);

        vm.prank(owner);
        presale.finalizePresale();

        assertEq(usdc.balanceOf(address(presale)), 0);
        assertEq(usdc.balanceOf(treasuryAddr), 50_000e6);
        assertTrue(presale.presaleFinalized());
        assertFalse(presale.presaleActive());
    }

    function test_FinalizeRevertsIfNotActive() public {
        // Never initialized → not active
        vm.prank(owner);
        vm.expectRevert(WebAI3Presale.PresaleNotActive.selector);
        presale.finalizePresale();
    }

    function test_FinalizeOnlyOwner() public {
        _initPresale();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        presale.finalizePresale();
    }

    // ════════════════════════════════════════════════
    //  9. PAUSE / UNPAUSE
    // ════════════════════════════════════════════════

    function test_PauseBlocksBuying() public {
        _initPresale();

        vm.prank(owner);
        presale.pause();

        _fundAndApprove(alice, 1_000e6);
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        presale.buyTokens(1_000e6);
    }

    function test_UnpauseRestoresBuying() public {
        _initPresale();

        vm.prank(owner);
        presale.pause();
        vm.prank(owner);
        presale.unpause();

        uint256 aic_ = _buy(alice, 1_000e6);
        assertGt(aic_, 0);
    }

    function test_PauseOnlyOwner() public {
        _initPresale();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        presale.pause();
    }

    // ════════════════════════════════════════════════
    //  10. BUY REVERTS
    // ════════════════════════════════════════════════

    function test_BuyRevertsIfNotActive() public {
        // Not initialized
        _fundAndApprove(alice, 100e6);
        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.PresaleNotActive.selector);
        presale.buyTokens(100e6);
    }

    function test_BuyRevertsOnZeroAmount() public {
        _initPresale();
        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.ZeroAmount.selector);
        presale.buyTokens(0);
    }

    function test_BuyRevertsIfPhaseExpired() public {
        _initPresale();
        // Warp past all phases
        WebAI3Presale.Phase memory last = presale.getPhaseInfo(PHASE_COUNT - 1);
        vm.warp(last.endTime);

        _fundAndApprove(alice, 100e6);
        vm.prank(alice);
        vm.expectRevert(WebAI3Presale.NoActivePhase.selector);
        presale.buyTokens(100e6);
    }

    // ════════════════════════════════════════════════
    //  11. VIEW FUNCTIONS
    // ════════════════════════════════════════════════

    function test_GetPresaleStatus() public {
        _initPresale();
        _buy(alice, 100_000e6); // $100k

        (
            uint256 activePhase,
            uint256 totalRaised,
            uint256 totalTokens,
            uint256 percentToHardCap,
            bool active
        ) = presale.getPresaleStatus();

        assertEq(activePhase, 0); // Still in Phase 1 ($100k < $500k)
        assertEq(totalRaised, 100_000e6);
        assertEq(totalTokens, (100_000e6 * 1e18) / 0.01e6);
        assertEq(percentToHardCap, 1); // (100k * 100) / 7M = 1%
        assertTrue(active);
    }

    function test_GetUserInfo() public {
        _initPresale();
        _buy(alice, 5_000e6);

        (uint256 contributed, uint256 allocated, bool claimed_) = presale.getUserInfo(alice);
        assertEq(contributed, 5_000e6);
        assertEq(allocated, (5_000e6 * 1e18) / 0.01e6);
        assertFalse(claimed_);
    }

    function test_GetUserInfoAfterClaim() public {
        _initPresale();
        _buy(alice, 1_000e6);

        vm.prank(owner);
        presale.finalizePresale();
        vm.warp(presale.tgeTime());
        vm.prank(alice);
        presale.claimTokens();

        (,, bool claimed_) = presale.getUserInfo(alice);
        assertTrue(claimed_);
    }

    // ════════════════════════════════════════════════
    //  12. PRICE CALCULATION ACCURACY
    // ════════════════════════════════════════════════

    function test_PriceCalculationPhase1() public {
        _initPresale();
        // $0.01/token → 1000 USDC = 100,000 AIC
        uint256 aic_ = _buy(alice, 1_000e6);
        assertEq(aic_, 100_000 ether);
    }

    function test_PriceCalculationPhase2() public {
        _initPresale();
        _buy(alice, 500_000e6); // Fill Phase 1

        // $0.013/token → 1300 USDC = 100,000 AIC
        uint256 aic_ = _buy(bob, 1_300e6);
        assertEq(aic_, 100_000 ether);
    }

    function test_PriceCalculationPhase7() public {
        _initPresale();

        // Fill phases 1-6 via fund-driven advance
        _buy(alice, 500_000e6); // Phase 1 cap
        _buy(alice, 500_000e6); // Phase 2 cap
        _buy(alice, 1_000_000e6); // Phase 3 cap
        _buy(alice, 1_500_000e6); // Phase 4 cap
        _buy(alice, 1_500_000e6); // Phase 5 cap
        _buy(alice, 1_000_000e6); // Phase 6 cap

        assertEq(presale.getActivePhase(), 6);

        // $0.070/token → 700 USDC = 10,000 AIC
        uint256 aic_ = _buy(bob, 700e6);
        assertEq(aic_, 10_000 ether);
    }

    function test_SmallPurchasePrecision() public {
        _initPresale();
        // 1 USDC ($0.000001) at $0.01 → 0.0001 AIC = 1e14 wei
        uint256 aic_ = _buy(alice, 1);
        assertEq(aic_, 1e18 / 0.01e6);
        assertEq(aic_, 100_000_000_000_000); // 1e14
    }

    // ════════════════════════════════════════════════
    //  13. FUZZ TESTS
    // ════════════════════════════════════════════════

    function testFuzz_BuyTokensInPhase1(uint256 usdcAmount) public {
        _initPresale();

        // Bound: 1 USDC unit to $500k (Phase 1 cap)
        usdcAmount = bound(usdcAmount, 1, 500_000e6);

        uint256 expectedAic = (usdcAmount * 1e18) / 0.01e6;

        // Check phase token cap
        vm.assume(expectedAic <= 50_000_000 ether);

        uint256 aic_ = _buy(alice, usdcAmount);
        assertEq(aic_, expectedAic);
        assertEq(presale.contributions(alice), usdcAmount);
        assertEq(presale.totalRaisedUSDC(), usdcAmount);
    }

    function testFuzz_CannotExceedHardCap(uint256 usdcAmount) public {
        // Single-phase presale with huge token cap
        WebAI3Presale.Phase[] memory phases = new WebAI3Presale.Phase[](1);
        phases[0] = WebAI3Presale.Phase({
            phaseCap: 7_000_000e6,
            pricePerToken: 0.01e6,
            maxTokens: 1_000_000_000 ether,
            startTime: block.timestamp,
            endTime: block.timestamp + 365 days,
            soldTokens: 0
        });

        vm.prank(owner);
        WebAI3Presale ps = new WebAI3Presale(address(usdc), address(aic), treasuryAddr);
        vm.prank(owner);
        ps.initializePresale(phases);

        usdcAmount = bound(usdcAmount, 1, 7_000_000e6);

        usdc.mint(alice, usdcAmount);
        vm.prank(alice);
        usdc.approve(address(ps), usdcAmount);
        vm.prank(alice);
        ps.buyTokens(usdcAmount);

        assertLe(ps.totalRaisedUSDC(), 7_000_000e6);
    }

    // ════════════════════════════════════════════════
    //  14. CONSTANTS
    // ════════════════════════════════════════════════

    function test_Constants() public view {
        assertEq(presale.HARD_CAP(), 7_000_000e6);
        assertEq(presale.PRESALE_ALLOCATION(), 500_000_000 ether);
        assertEq(presale.TGE_DELAY(), 7 days);
    }

    // ════════════════════════════════════════════════
    //  15. EVENTS
    // ════════════════════════════════════════════════

    function test_BuyEmitsTokensPurchasedEvent() public {
        _initPresale();

        uint256 usdcAmount = 1_000e6;
        uint256 expectedAic = (usdcAmount * 1e18) / 0.01e6;

        _fundAndApprove(alice, usdcAmount);

        vm.expectEmit(true, true, false, true);
        emit WebAI3Presale.TokensPurchased(alice, usdcAmount, expectedAic, 0);

        vm.prank(alice);
        presale.buyTokens(usdcAmount);
    }

    function test_ClaimEmitsTokensClaimedEvent() public {
        _initPresale();
        uint256 aicAmount = _buy(alice, 1_000e6);

        vm.prank(owner);
        presale.finalizePresale();
        vm.warp(presale.tgeTime());

        vm.expectEmit(true, false, false, true);
        emit WebAI3Presale.TokensClaimed(alice, aicAmount);

        vm.prank(alice);
        presale.claimTokens();
    }

    function test_FinalizeEmitsPresaleFinalizedEvent() public {
        _initPresale();
        _buy(alice, 1_000e6);

        vm.expectEmit(false, false, false, true);
        emit WebAI3Presale.PresaleFinalized(1_000e6, (1_000e6 * 1e18) / 0.01e6);

        vm.prank(owner);
        presale.finalizePresale();
    }

    // ════════════════════════════════════════════════
    //  16. END-TO-END SCENARIO
    // ════════════════════════════════════════════════

    function test_EndToEnd_FullPresaleLifecycle() public {
        _initPresale();

        // ── Phase 1: Alice buys $10k ──
        uint256 aliceAic = _buy(alice, 10_000e6);
        assertEq(presale.getActivePhase(), 0);

        // ── Phase 1: Bob buys $490k → fills Phase 1 ──
        uint256 bobAic = _buy(bob, 490_000e6);
        assertEq(presale.getActivePhase(), 1); // Now in Phase 2

        // ── Phase 2: Carol buys $5k at Phase 2 price ──
        uint256 carolAic = _buy(carol, 5_000e6);
        uint256 expectedCarolAic = (uint256(5_000e6) * 1e18) / 13_000;
        assertEq(carolAic, expectedCarolAic);

        // ── Owner finalizes ──
        vm.prank(owner);
        presale.finalizePresale();

        assertTrue(presale.presaleFinalized());
        assertEq(usdc.balanceOf(treasuryAddr), 505_000e6);

        // ── Warp to TGE and claim ──
        vm.warp(presale.tgeTime());

        vm.prank(alice);
        presale.claimTokens();
        assertEq(aic.balanceOf(alice), aliceAic);

        vm.prank(bob);
        presale.claimTokens();
        assertEq(aic.balanceOf(bob), bobAic);

        vm.prank(carol);
        presale.claimTokens();
        assertEq(aic.balanceOf(carol), carolAic);

        // Verify total tokens sold
        assertEq(presale.totalTokensSold(), aliceAic + bobAic + carolAic);
        assertEq(presale.totalRaisedUSDC(), 505_000e6);
    }
}
