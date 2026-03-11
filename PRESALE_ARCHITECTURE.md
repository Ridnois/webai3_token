# WebAI3 Token Presale Architecture

**Document Version:** 1.0
**Status:** Technical Design
**Target Audience:** Smart Contract Engineers, Protocol Architects, Crypto Investors
**Last Updated:** March 2026

---

## Executive Summary

This document describes the technical architecture, mechanics, and implementation strategy for the WebAI3 Token (AIC) presale. The presale is designed to raise **$5M USD** through a **hybrid, fund-driven phase system** with optional time-based fallbacks. Early-phase investors enjoy 10x price appreciation incentives, creating strong demand dynamics and community engagement.

The system is implemented through three coordinated smart contracts:
1. **PresaleContract** — Manages contributions, token allocation, and phase transitions
2. **TreasuryContract** — Holds raised funds and distributes according to governance
3. **WebAI3Token** — Standard ERC-20 with allocation, vesting, and governance features

---

## 1. Presale Overview

### Purpose

The presale serves four critical functions:

**1. Liquidity Bootstrap**
- Raises $5M to fund initial liquidity pools (DEX pair seeding)
- Enables fair market price discovery post-launch
- Prevents launch-day liquidity crisis

**2. Development Funding**
- Allocates proceeds to protocol development
- Funds infrastructure, security audits, and ecosystem tools
- Sustainable runway for core team

**3. Token Distribution**
- Distributes 50% of token supply to early community members
- Aligns incentives through early-stage ownership
- Creates decentralized holder base

**4. Market Narrative & Adoption**
- Demonstrates product-market fit and investor confidence
- Creates FOMO and organic marketing through phase progression
- Price appreciation (10x from Phase 1 to listing) signals success

### Presale Target & Pricing

| Metric | Value | Notes |
|---|---|---|
| **Total Raise Target** | $5,000,000 | Hard cap |
| **Token Supply (Total)** | 1,000,000,000 AIC | Fixed, immutable |
| **Presale Allocation** | 500,000,000 AIC (50%) | Distributed to buyers |
| **Phase 1 Price** | $0.01 | Entry price (lowest) |
| **Phase 4 Price** | $0.04 | Late phase (4x Phase 1) |
| **Listing Price Target** | $0.08 | Post-launch market price (2x Phase 4) |
| **Max Presale Investor Return** | 8x | Phase 1 → Listing (0.01 → 0.08) |

### Incentive Structure

The presale creates powerful price appreciation dynamics:

- **Phase 1 Early Birds:** 0.01 USDC per token → 8x to listing
- **Phase 2 Participants:** 0.015 USDC per token → 5.3x to listing
- **Phase 3 Participants:** 0.025 USDC per token → 3.2x to listing
- **Phase 4 Latecomers:** 0.04 USDC per token → 2x to listing

This incentivizes participation in earlier phases and creates a natural "push" through phases as investors seek better prices.

---

## 2. Presale Model: Hybrid Fund-Driven System

### Phase Structure

The presale progresses through **four phases** based on **cumulative funds raised**. Each phase has:
- A funding target range (triggers transition when reached)
- A token price (increases per phase)
- A token allocation cap
- Optional time-based fallback (phase ends if time expires)

| Phase | Raise Range | Price | Allocation | Duration |
|---|---|---|---|---|
| Phase 1 | $0 – $500k | $0.01 | 50M AIC | 14 days |
| Phase 2 | $500k – $1.5M | $0.015 | 66.67M AIC | 21 days |
| Phase 3 | $1.5M – $3M | $0.025 | 60M AIC | 28 days |
| Phase 4 | $3M – $5M | $0.04 | 313.33M AIC | 35 days |

**Total Presale Allocation:** 500M AIC (50% of supply)

### Phase Transition Logic

**Primary Trigger:** Cumulative funds raised
```
if totalRaisedUSDC >= phaseCap:
    advance to next phase
    updatePricePerToken()
```

**Secondary Trigger:** Time-based fallback
```
if block.timestamp >= phaseDeadline AND totalRaisedUSDC >= phaseMinimum:
    advance to next phase (even if cap not reached)
```

**Example Scenario:**
- Phase 1 opens at Day 0 with $0.01 price
- Phase 1 reaches $500k on Day 5
- Contract automatically transitions to Phase 2 at $0.015 price
- Investors who waited are now charged 50% more per token

This creates urgency and strong incentive to buy early.

### Failure Cases

**Hard Cap Reached:** If $5M is raised before Phase 4 ends, presale closes immediately.

**Phase Expires:** If a phase reaches its time deadline without progressing to next phase:
- Phase remains open at current price
- Tokens remain claimable at locked price
- Presale can be manually extended by governance

---

## 3. Smart Contract Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────┐
│                  WebAI3 Presale System                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  User Wallet                                            │
│     │                                                   │
│     ├──→ [USDC] ──────────────────┐                     │
│     │                             │                     │
│     └──→ [ETH] ──────────────────┬┴────────────┐        │
│                                  │             │        │
│                        ┌─────────▼─────────┐  │        │
│                        │ PresaleContract   │◄─┘        │
│                        │ (accepts payments)│           │
│                        └─────────┬─────────┘           │
│                                  │                     │
│                    ┌─────────────┼─────────────┐       │
│                    │             │             │       │
│            ┌───────▼────┐ ┌─────▼────┐ ┌─────▼────┐  │
│            │ Treasury   │ │ AIC Token │ │ Vesting  │  │
│            │ (multisig) │ │ (ERC20)   │ │ (team)   │  │
│            └────────────┘ └───────────┘ └──────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.1 PresaleContract

**Primary Responsibility:** Manage presale flow, accept payments, track allocations.

**Key State Variables:**

```solidity
// Phase configuration
struct Phase {
    uint256 startTime;           // Unix timestamp
    uint256 endTime;             // Time-based fallback
    uint256 phaseCap;            // Funding target (e.g., 500k USDC)
    uint256 pricePerToken;       // USDC per AIC (1e6 decimals)
    uint256 maxTokensPhase;      // Token allocation per phase
    uint256 soldTokensPhase;     // Running total (state)
}

// Global state
uint256 public totalRaisedUSDC;  // Cumulative funds
uint256 public totalTokensSold;  // Cumulative token allocation
uint256 public hardCap = 5_000_000e6;  // $5M in USDC (6 decimals)

mapping(address => uint256) public contributions;  // USDC per user
mapping(address => uint256) public tokenAllocated;  // AIC per user
mapping(address => bool) public claimed;  // Post-TGE claim flag

Phase[] public phases;  // Array of 4 phases
bool public presaleActive;  // Start/stop flag
```

**Key Functions:**

```solidity
// Admin: Initialize presale
function initializePresale(Phase[] memory _phases) external onlyOwner

// User: Buy tokens
function buyTokens(uint256 usdcAmount) external returns (uint256 aicAmount)
    - Validate presale is active
    - Get current phase via getActivePhase()
    - Calculate AIC: aicAmount = usdcAmount / pricePerToken
    - Validate phase allocation not exceeded
    - Transfer USDC to treasury
    - Record contribution and allocation
    - Emit BuyTokens event
    - Return aicAmount

// View: Get active phase
function getActivePhase() public view returns (uint256 phaseIndex)
    - Loop through phases
    - Find phase where block.timestamp in [startTime, endTime)
    - If totalRaisedUSDC >= phaseCap, return next phase
    - Return type(uint256).max if no active phase

// View: Get presale progress
function getPresaleStatus() external view returns (
    uint256 activePhase,
    uint256 totalRaised,
    uint256 totalTokens,
    uint256 percentToHardCap
)

// User: Claim tokens post-TGE
function claimTokens() external
    - Require presaleEnded && tgeTime <= block.timestamp
    - Require tokenAllocated[msg.sender] > 0
    - Require !claimed[msg.sender]
    - Transfer AIC tokens to user
    - Mark claimed[msg.sender] = true

// Admin: Finalize presale (locks contributions)
function finalizePresale() external onlyOwner
    - Require presaleEnded && hardCap reached
    - Transfer funds to treasury
    - Emit PresaleFinalized event
```

### 3.2 TreasuryContract

**Primary Responsibility:** Hold funds, distribute according to allocation, controlled by governance multisig.

**Responsibilities:**

```solidity
contract Treasury {
    address public multisig;  // 2-of-3 multisig (team + investor reps)

    // Fund allocation after presale
    mapping(address => uint256) public allocations;

    // Post-presale, distribute:
    // - 60% to liquidity pools (DEX)
    // - 20% to development
    // - 10% to team (vested over 4 years)
    // - 10% to marketing & partnerships
}
```

**Fund Flow:**

1. **Presale Phase:** PresaleContract forwards all USDC to Treasury
2. **Post-Presale (Day 1-7):** Treasury multisig approves liquidity provision
3. **Liquidity Provision:** Treasury deposits 60% ($3M) + 300M AIC tokens to DEX
4. **Remaining Funds:** 40% ($2M) held for development and operations

### 3.3 WebAI3Token Contract

**Primary Responsibility:** ERC-20 token with allocation and optional vesting for team.

**Token Allocation at Deployment:**

```solidity
struct Allocation {
    address recipient;
    uint256 amount;
}

// Total: 1,000,000,000 AIC (1e27 base units)
Allocation[] memory allocations = [
    {recipient: presaleContract,    amount: 500_000_000 ether},   // 50%
    {recipient: liquidityReserve,   amount: 200_000_000 ether},   // 20%
    {recipient: ecosystemFund,      amount: 100_000_000 ether},   // 10%
    {recipient: teamVestingContract,amount: 100_000_000 ether},   // 10%
    {recipient: treasury,           amount: 100_000_000 ether}    // 10%
];
```

**Team Token Vesting:**
- 4-year linear vesting (1% per month)
- 1-year cliff (no tokens released in first 12 months)
- Controlled by separate VestingContract

---

## 4. Presale Mechanics

### User Flow

```
Step 1: Connect Wallet
├─ User visits presale.webai3.io
├─ Connects MetaMask/Wallet to Base Sepolia testnet
└─ UI displays current phase, price, progress

Step 2: Approve USDC Spending
├─ User clicks "Approve USDC"
├─ MetaMask prompts signature
├─ User authorizes PresaleContract to spend USDC
└─ Approval appears on-chain

Step 3: Enter Amount & Buy
├─ User inputs 100 USDC
├─ UI calculates: 100 USDC / 0.01 = 10,000 AIC
├─ User clicks "Buy Tokens"
├─ MetaMask prompts transaction signature
└─ Transaction submitted to mempool

Step 4: Confirmation
├─ Contract receives 100 USDC from user wallet
├─ Contract records 10,000 AIC allocation to user
├─ User sees confirmation: "10,000 AIC reserved"
└─ totalRaisedUSDC increments to track phase progress

Step 5: Phase Advancement (Automatic)
├─ If totalRaisedUSDC >= $500k:
│  ├─ Contract transitions to Phase 2
│  ├─ Price changes to $0.015 per token
│  └─ UI updates to show Phase 2 active
└─ If block.timestamp >= phaseEnd AND no phase cap:
   ├─ Phase time expires
   └─ Presale locked at current price

Step 6: Token Claim (Post-TGE)
├─ After presale ends and TGE date arrives
├─ User returns to presale.webai3.io
├─ Clicks "Claim Tokens"
├─ Contract transfers allocated AIC to user wallet
└─ User now owns tokens, can trade/stake/vote
```

### Purchase Pseudocode

```solidity
function buyTokens(uint256 usdcAmount) external {
    // Validation
    require(presaleActive, "Presale not active");
    require(usdcAmount > 0, "Amount must be > 0");
    require(totalRaisedUSDC < hardCap, "Hard cap reached");

    // Get current phase
    uint256 phaseIdx = getActivePhase();
    Phase storage phase = phases[phaseIdx];
    require(block.timestamp < phase.endTime, "Phase expired");

    // Calculate tokens owed
    uint256 price = phase.pricePerToken;  // e.g., 0.01e6 = $0.01
    uint256 aicAmount = (usdcAmount * 1e18) / price;

    // Validate phase cap (tokens)
    require(
        phase.soldTokensPhase + aicAmount <= phase.maxTokensPhase,
        "Phase token cap exceeded"
    );

    // Validate hard cap (funds)
    require(
        totalRaisedUSDC + usdcAmount <= hardCap,
        "Hard cap exceeded"
    );

    // Transfer USDC from user to treasury
    USDC.safeTransferFrom(msg.sender, treasury, usdcAmount);

    // Record allocation
    contributions[msg.sender] += usdcAmount;
    tokenAllocated[msg.sender] += aicAmount;

    // Update global state
    totalRaisedUSDC += usdcAmount;
    totalTokensSold += aicAmount;
    phase.soldTokensPhase += aicAmount;

    // Check if phase cap reached → auto-transition
    if (totalRaisedUSDC >= phase.phaseCap && phaseIdx < phases.length - 1) {
        // Phase 1 → Phase 2 (or Phase 2 → Phase 3, etc.)
        emit PhaseAdvanced(phaseIdx + 1, phases[phaseIdx + 1].pricePerToken);
    }

    // Check if hard cap reached → presale ends
    if (totalRaisedUSDC >= hardCap) {
        presaleActive = false;
        emit PresaleEnded(totalRaisedUSDC, totalTokensSold);
    }

    emit BuyTokens(msg.sender, usdcAmount, aicAmount, phaseIdx);
}
```

---

## 5. Phase Transition Logic

### Automatic Transitions (Fund-Based)

When cumulative funds reach phase cap, the presale **automatically advances** to the next phase.

**Example Timeline:**

```
Day 0, 10:00 UTC — Phase 1 Begins
├─ Price: $0.01 per AIC
├─ Target: $500k
└─ Time limit: 14 days (unless cap hit sooner)

Day 4, 15:30 UTC — $500k Raised
├─ Contract detects totalRaisedUSDC >= $500,000
├─ Phase 1 closes immediately
├─ Phase 2 begins instantly
├─ Price: $0.015 per AIC
└─ Emit: PhaseAdvanced(phase=2, price=0.015e6)

Day 5, 08:00 UTC — New Buyer Tries to Buy
├─ Calls buyTokens(1000 USDC)
├─ getActivePhase() returns 2 (Phase 2)
├─ Price applied: $0.015 per token
├─ Tokens allocated: 1000 / 0.015 = 66,667 AIC
├─ User realizes they paid 50% more than 24 hours ago
└─ FOMO effect drives faster Phase 2 completion

Day 23, 19:45 UTC — $1.5M Raised
├─ Phase 2 cap reached
├─ Phase 3 begins immediately
├─ Price: $0.025 per AIC
└─ 2.5x increase from Phase 1 entry price
```

### Time-Based Fallback (Soft Deadline)

If a phase reaches its deadline without hitting the funding cap, the phase extends at locked price.

**Example (Phase 1 Timeout):**

```
Day 14, 10:00 UTC (Phase 1 Deadline)
├─ totalRaisedUSDC = $450k (did not reach $500k cap)
├─ Contract checks: block.timestamp >= phase[1].endTime
├─ Result: Phase 1 does NOT auto-advance
├─ Phase 1 remains open at $0.01 price
├─ Buyers can continue purchasing until hard cap or manual close
└─ Governance can vote to extend Phase 1 or force Phase 2
```

### Hard Cap & Presale Closure

If $5M is raised at any point, the presale stops immediately.

```solidity
function buyTokens(uint256 usdcAmount) external {
    // ...
    require(totalRaisedUSDC + usdcAmount <= hardCap, "Hard cap exceeded");

    // After update:
    totalRaisedUSDC += usdcAmount;

    if (totalRaisedUSDC >= hardCap) {
        presaleActive = false;
        emit PresaleEnded(totalRaisedUSDC, totalTokensSold);
    }
}
```

---

## 6. Security Considerations

### Reentrancy Protection

**Threat:** User calls `buyTokens()`, contract calls external token transfer, attacker's fallback reenters and calls `buyTokens()` again.

**Mitigation:**
- Use OpenZeppelin `ReentrancyGuard` on `buyTokens()`
- Follow Checks-Effects-Interactions pattern: validate → update state → transfer

```solidity
function buyTokens(uint256 usdcAmount) external nonReentrant {
    // Checks
    require(presaleActive, "...");

    // Effects
    contributions[msg.sender] += usdcAmount;
    tokenAllocated[msg.sender] += aicAmount;
    totalRaisedUSDC += usdcAmount;

    // Interactions
    USDC.safeTransferFrom(msg.sender, treasury, usdcAmount);
}
```

### Overflow & Underflow Protection

**Solidity 0.8.24** has built-in overflow protection, but:
- Use `uint256` consistently (no mixed sizes)
- Watch for precision loss in division: `aicAmount = usdcAmount * 1e18 / price`

### Safe ERC20 Transfers

Always use `SafeERC20` wrapper:

```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

USDC.safeTransferFrom(msg.sender, treasury, usdcAmount);
AIC.safeTransfer(msg.sender, aicAmount);
```

This guards against tokens that don't return `bool` on transfer.

### Multisig Treasury Control

**Threat:** Single admin account compromised, funds stolen.

**Mitigation:**
- Treasury controlled by **2-of-3 multisig** (e.g., Gnosis Safe)
- Signers: Founder, early investor, community representative
- No emergency withdrawal without 2 signatures
- All fund movements require proposal + voting

### Pausable Contract

```solidity
function pause() external onlyOwner
function unpause() external onlyOwner

function buyTokens(uint256 amount) external whenNotPaused { ... }
```

Allows admin to freeze presale if security issue detected (e.g., oracle manipulation).

### Per-Wallet Contribution Caps (Optional)

**Threat:** Single whale accumulates > 10% of tokens, creates manipulation risk.

**Optional Mitigation:**

```solidity
mapping(address => uint256) public maxContributionPerWallet = 250_000e6;  // $250k max

function buyTokens(uint256 usdcAmount) external {
    require(
        contributions[msg.sender] + usdcAmount <= maxContributionPerWallet,
        "Per-wallet cap exceeded"
    );
    // ...
}
```

Prevents whale dominance, but may reduce funding speed. Disable for phase 4 to ensure hard cap is hit.

### Price Precision

**Risk:** Rounding error in token calculation.

Example with Phase 1 ($0.01 = 1e6 USDC units):

```
Input: 100 USDC = 100e6 units
Calculation: (100e6 * 1e18) / 1e6 = 100e18 = 100 AIC tokens ✓

Edge case (1 wei USDC):
Calculation: (1 * 1e18) / 1e6 = 1e12 = 0.000001 AIC ✓
```

Rounding down is acceptable (buyer loses dust, not material).

---

## 7. Liquidity Strategy

### Post-Presale Liquidity Provision

Upon presale completion, the DAO will provide liquidity to ensure stable launch.

**Fund Allocation After $5M Raise:**

| Category | Amount | Purpose |
|---|---|---|
| **DEX Liquidity** | $3.0M (60%) | Uniswap v3 / Curve pool |
| **Development** | $1.0M (20%) | Engineering, security, ops |
| **Team Reserves** | $0.5M (10%) | Operations, payroll buffer |
| **Marketing** | $0.5M (10%) | Community growth, partnerships |

### Liquidity Pool Design

**Pair:** AIC / USDC on Base L2 (Uniswap v3)

**Depth Requirement:**
- $3M USDC + 37.5M AIC tokens
- Creates mid-price ~$0.08 (2x Phase 4 entry, 8x Phase 1 entry)
- Provides 24-hour trading volume cushion: ~$5M at 2% slippage

**Why Deep Liquidity Matters:**

1. **Launch Stability** — Prevents 100% price swings on day 1
2. **Investor Confidence** — Buyers know they can exit without massive slippage
3. **Market Credibility** — Professional-grade liquidity signals serious project
4. **Arbitrage Prevention** — Stops bots from exploiting price gaps across DEXes

---

## 8. Token Distribution

### Total Supply Allocation

**1,000,000,000 AIC (1B tokens, 18 decimals)**

| Category | Amount | % | Vesting |
|---|---|---|---|
| **Presale** | 500M | 50% | Immediate (on claim) |
| **Liquidity Reserve** | 200M | 20% | Locked in DEX pool (6 months) |
| **Ecosystem / Grants** | 100M | 10% | Vesting (2 years, linear) |
| **Team** | 100M | 10% | Vesting (4 years, 1y cliff) |
| **Treasury** | 100M | 10% | Governance controlled |

### Vesting Schedules

**Presale Tokens:**
- Distribution: Immediate upon TGE (token generation event)
- No vesting lock (users can trade day 1)
- Encourages early participation

**Team Tokens (100M):**
- Cliff: 12 months (0 tokens released)
- Vesting: 36 months linear (1/36 per month after cliff)
- Prevented via smart contract (cannot be transferred until released)

**Ecosystem Grants (100M):**
- Allocated to developer grants, protocol incentives
- Linear vesting over 24 months
- Released to incentive programs monthly

**Liquidity Reserve (200M):**
- Locked in Uniswap v3 pool
- Cannot be withdrawn for 6 months
- Ensures floor liquidity during launch phase

---

## 9. Launch Process

### Timeline

| Phase | Date | Action |
|---|---|---|
| **T-30 days** | Feb 10, 2026 | Contracts audited, deployed to testnet |
| **T-14 days** | Feb 24, 2026 | Presale whitelist opens (optional KYC) |
| **T-7 days** | Mar 3, 2026 | Marketing campaign, community discussions |
| **T-0 (TGE)** | Mar 10, 2026 | Presale Phase 1 opens, Phase 1 begins |
| **T+5 days** | Mar 15, 2026 | Expected Phase 2 transition (if $500k raised) |
| **T+20 days** | Mar 30, 2026 | Expected Phase 3 transition (if $1.5M raised) |
| **T+40 days** | Apr 19, 2026 | Expected Phase 4 transition (if $3M raised) |
| **T+60 days** | May 9, 2026 | Presale closes (hard cap or deadline) |
| **T+70 days** | May 19, 2026 | Liquidity provision (DEX listing) |
| **T+75 days** | May 24, 2026 | Airdrop/token claim enabled |

### Deployment Sequence

1. **Deploy Token Contract**
   ```
   → WebAI3Token(admin=multisig, allocations=[...])
   → Total supply: 1B AIC minted and distributed
   → Address recorded: 0xABC...
   ```

2. **Deploy Treasury Contract**
   ```
   → TreasuryContract(multisig=2-of-3 signers)
   → Grants presale contract permission to forward funds
   ```

3. **Deploy Presale Contract**
   ```
   → PresaleContract(
        usdc=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
        aic=0xABC...,
        treasury=0xDEF...
      )
   → Initialize phases[0..3]
   → Grant presale contract permission to distribute tokens
   ```

4. **Final Validations**
   ```
   ✓ Token total supply = 1B AIC
   ✓ Presale allocation = 500M AIC (in presale contract)
   ✓ All addresses correct (no typos)
   ✓ Phase prices: 0.01, 0.015, 0.025, 0.04
   ✓ Phase caps: $500k, $1.5M, $3M, $5M cumulative
   ✓ Hard cap: $5M total
   ```

5. **Enable Presale**
   ```
   → setPresaleActive(true)
   → Phase 1 begins, accepting buys
   ```

6. **After Presale Closes**
   ```
   → finalizePresale() called by multisig
   → Transfers treasury funds to DEX liquidity pool
   → Mints liquidity provider tokens (LP tokens)
   → Unlocks token claims for users (claimTokens() enabled)
   ```

7. **User Claims & Trading**
   ```
   → Users call claimTokens() to receive AIC
   → Users trade on Uniswap: AIC ↔ USDC
   → Price discovered by market forces
   → Target listing price: $0.08 (2x Phase 4 entry, 8x Phase 1)
   ```

---

## 10. Future Extensions

### Phase 2: Dynamic Bonding Curve

**Objective:** Smoother price progression and continuous buy/sell mechanism.

**Mechanism:**
- Replace discrete phases with continuous bonding curve
- Price = `basePrice * (totalSupplyMinted / hardCap) ^ 2`
- Users can buy/sell at any time (not phase-gated)
- Automatic price discovery

**Pros:**
- Fair pricing for all buyers
- Continuous supply (not phase caps)
- Natural market stability

**Cons:**
- Requires more complex math
- Less FOMO/urgency (no phase transitions)
- May be harder for retail to understand

### Phase 2: Onchain Governance

**Objective:** Decentralize presale decisions via DAO voting.

**Mechanisms:**
- Token holders vote to extend phases
- Vote to adjust prices dynamically
- Treasury fund allocation controlled by governance
- Team vesting schedule adjustable via proposal

**Contract Integration:**
```solidity
// Governor contract (OpenZeppelin)
// Proposals to:
// - setPresaleActive(false)
// - adjustPhasePrice(phaseIdx, newPrice)
// - markPresaleFailed()
```

### Phase 3: Revenue Sharing

**Objective:** Token holders receive portion of inference API fees.

**Flow:**
1. Users pay in USDC for AI model inference
2. Protocol collects 10% fee on each transaction
3. Revenue distributed to AIC token stakers (weekly)
4. Staking yield: ~15-20% APY (depends on adoption)

**Contract:**
```solidity
contract RevenueShare {
    mapping(address => uint256) public staked;
    uint256 public weeklyRevenue;

    function claimRewards() external
        → Returns (weeklyRevenue * stakedAmount / totalStaked)
}
```

### Phase 3: Secondary Markets & Perpetuals

**Objective:** Enable derivatives trading on AIC token.

**Integrations:**
- Listing on Binance / Coinbase / Kraken
- Perpetual futures on dYdX / GMX (leverage trading)
- Options markets (Dopex, Lyra)
- Creates deeper liquidity and adoption

---

## Appendix: Key Formulas

### Token Allocation Calculation

```
aicAmount = (usdcAmount × 10^18) / pricePerToken

Example (Phase 1):
- Input: 100 USDC
- Price: 0.01e6 (0.01 * 10^6 USDC units, 6 decimals)
- Calculation: (100 × 10^6 × 10^18) / 1 × 10^6 = 10,000 × 10^18 AIC
- Result: 10,000 AIC tokens
```

### Price Per Token (in USDC with 6 decimals)

```
Phase 1: 0.01 USDC = 10,000 USDC (per 1M AIC)
Phase 2: 0.015 USDC = 15,000 USDC (per 1M AIC)
Phase 3: 0.025 USDC = 25,000 USDC (per 1M AIC)
Phase 4: 0.04 USDC = 40,000 USDC (per 1M AIC)
```

### Presale Progress

```
Progress % = (totalRaisedUSDC / hardCap) × 100
           = (totalRaisedUSDC / 5,000,000) × 100

Example: $1.5M raised = (1.5M / 5M) × 100 = 30% complete
```

---

## References

- **Solidity 0.8.24:** https://docs.soliditylang.org
- **OpenZeppelin Contracts v5:** https://docs.openzeppelin.com/contracts/5.x
- **ERC-20 Standard:** https://eips.ethereum.org/EIPS/eip-20
- **Base L2:** https://base.org
- **Uniswap v3:** https://uniswap.org
- **ReentrancyGuard:** https://docs.openzeppelin.com/contracts/5.x/api/security

---

**Document Status:** Complete
**Next Steps:** Smart contract implementation and security audit
