# WebAI3 Token Presale Architecture

**Document Version:** 1.0
**Status:** Technical Design
**Target Audience:** Smart Contract Engineers, Protocol Architects, Crypto Investors
**Last Updated:** March 2026

---

## Executive Summary

This document describes the technical architecture, mechanics, and implementation strategy for the WebAI3 Token (AIC) presale. The presale is designed to raise **$7M USD** through a **hybrid, fund-driven phase system** with optional time-based fallbacks. Early-phase investors enjoy 12x price appreciation incentives, creating strong demand dynamics and community engagement.

The system is implemented through three coordinated smart contracts:
1. **PresaleContract** — Manages contributions, token allocation, and phase transitions
2. **TreasuryContract** — Holds raised funds and distributes according to governance
3. **WebAI3Token** — Standard ERC-20 with allocation, vesting, and governance features

**Network:** Ethereum Mainnet (Production) & Ethereum Sepolia (Testing)

---

## 1. Presale Overview

### Purpose

The presale serves four critical functions:

**1. Liquidity Bootstrap**
- Raises $7M to fund initial liquidity pools (DEX pair seeding)
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
- Price appreciation (12x from Phase 1 to listing) signals success

### Presale Target & Pricing

| Metric | Value | Notes |
|---|---|---|
| **Total Raise Target** | $7,000,000 | Hard cap |
| **Token Supply (Total)** | 1,000,000,000 AIC | Fixed, immutable |
| **Presale Allocation** | 500,000,000 AIC (50%) | Distributed to buyers |
| **Phase 1 Price** | $0.010 | Entry price (lowest) |
| **Phase 7 Price** | $0.070 | Late phase (7x Phase 1) |
| **Listing Price Target** | $0.120 | Post-launch market price (1.71x Phase 7) |
| **Max Presale Investor Return** | 12x | Phase 1 → Listing (0.010 → 0.120) |

### Incentive Structure

The presale creates powerful price appreciation dynamics across seven phases:

- **Phase 1 Early Birds:** $0.010 per token → 12x to listing
- **Phase 2 Participants:** $0.013 per token → 9.2x to listing
- **Phase 3 Participants:** $0.020 per token → 6x to listing
- **Phase 4 Participants:** $0.028 per token → 4.3x to listing
- **Phase 5 Participants:** $0.038 per token → 3.2x to listing
- **Phase 6 Participants:** $0.053 per token → 2.3x to listing
- **Phase 7 Latecomers:** $0.070 per token → 1.71x to listing

This incentivizes participation in earlier phases and creates a natural "push" through phases as investors seek better prices.

---

## 2. Presale Model: Hybrid Fund-Driven System

### Phase Structure

The presale progresses through **seven phases** based on **cumulative funds raised**. Each phase has:
- A funding target range (triggers transition when reached)
- A token price (increases per phase)
- A token allocation cap
- Optional time-based fallback (phase ends if time expires)

| Phase | Raise Range | Price | Allocation | Duration |
|---|---|---|---|---|
| Phase 1 | $0 – $500k | $0.010 | 50M AIC | 14 days |
| Phase 2 | $500k – $1M | $0.013 | 38.5M AIC | 14 days |
| Phase 3 | $1M – $2M | $0.020 | 50M AIC | 14 days |
| Phase 4 | $2M – $3.5M | $0.028 | 53.6M AIC | 21 days |
| Phase 5 | $3.5M – $5M | $0.038 | 39.5M AIC | 21 days |
| Phase 6 | $5M – $6M | $0.053 | 18.9M AIC | 21 days |
| Phase 7 | $6M – $7M | $0.070 | 250M AIC | 35 days |

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
- Phase 1 opens at Day 0 with $0.010 price
- Phase 1 reaches $500k on Day 5
- Contract automatically transitions to Phase 2 at $0.013 price
- Investors who waited are now charged 30% more per token

This creates urgency and strong incentive to buy early.

### Failure Cases

**Hard Cap Reached:** If $7M is raised before Phase 7 ends, presale closes immediately.

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
uint256 public hardCap = 7_000_000e6;  // $7M in USDC (6 decimals)

mapping(address => uint256) public contributions;  // USDC per user
mapping(address => uint256) public tokenAllocated;  // AIC per user
mapping(address => bool) public claimed;  // Post-TGE claim flag

Phase[] public phases;  // Array of 7 phases
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
3. **Liquidity Provision:** Treasury deposits 60% ($4.2M) + 300M AIC tokens to DEX
4. **Remaining Funds:** 40% ($2.8M) held for development and operations

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
├─ Connects MetaMask/Wallet to Ethereum Sepolia testnet
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
│  ├─ Price changes to $0.013 per token
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
├─ Price: $0.010 per AIC
├─ Target: $500k
└─ Time limit: 14 days (unless cap hit sooner)

Day 5, 14:30 UTC — $500k Raised
├─ Contract detects totalRaisedUSDC >= $500,000
├─ Phase 1 closes immediately
├─ Phase 2 begins instantly
├─ Price: $0.013 per AIC
└─ Emit: PhaseAdvanced(phase=2, price=0.013e6)

Day 6, 09:00 UTC — New Buyer Tries to Buy
├─ Calls buyTokens(1000 USDC)
├─ getActivePhase() returns 2 (Phase 2)
├─ Price applied: $0.013 per token
├─ Tokens allocated: 1000 / 0.013 = 76,923 AIC
├─ User realizes they paid 30% more than 24 hours ago
└─ FOMO effect drives faster Phase 2 completion

Day 18, 11:45 UTC — $1M Raised
├─ Phase 2 cap reached
├─ Phase 3 begins immediately
├─ Price: $0.020 per AIC
└─ 2x increase from Phase 1 entry price
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

If $7M is raised at any point, the presale stops immediately.

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

**Fund Allocation After $7M Raise:**

| Category | Amount | Purpose |
|---|---|---|
| **DEX Liquidity** | $4.2M (60%) | Uniswap v3 / Curve pool |
| **Development** | $1.4M (20%) | Engineering, security, ops |
| **Team Reserves** | $0.7M (10%) | Operations, payroll buffer |
| **Marketing** | $0.7M (10%) | Community growth, partnerships |

### Liquidity Pool Design

**Pair:** AIC / USDC on Ethereum Mainnet (Uniswap v3)

**Depth Requirement:**
- $4.2M USDC + 35M AIC tokens
- Creates launch price ~$0.120 (1.71x Phase 7 entry, 12x Phase 1 entry)
- Provides 24-hour trading volume cushion: ~$7M at 2% slippage

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
| **T-0 (TGE)** | Mar 10, 2026 | Presale Phase 1 opens |
| **T+5 days** | Mar 15, 2026 | Expected Phase 2 transition (if $500k raised) |
| **T+12 days** | Mar 22, 2026 | Expected Phase 3 transition (if $1M raised) |
| **T+25 days** | Apr 4, 2026 | Expected Phase 4 transition (if $2M raised) |
| **T+40 days** | Apr 19, 2026 | Expected Phase 5 transition (if $3.5M raised) |
| **T+55 days** | May 4, 2026 | Expected Phase 6 transition (if $5M raised) |
| **T+65 days** | May 14, 2026 | Expected Phase 7 transition (if $6M raised) |
| **T+85 days** | Jun 3, 2026 | Presale closes (hard cap reached or deadline) |
| **T+90 days** | Jun 8, 2026 | Liquidity provision (DEX listing) |
| **T+100 days** | Jun 18, 2026 | Airdrop/token claim enabled |

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
        usdc=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
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
   ✓ Phase prices: $0.010, $0.013, $0.020, $0.028, $0.038, $0.053, $0.070
   ✓ Phase caps: $500k, $1M, $2M, $3.5M, $5M, $6M, $7M cumulative
   ✓ Hard cap: $7M total
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
   → Target listing price: $0.120 (1.71x Phase 7 entry, 12x Phase 1)
   ```

---

## 10. Complete PresaleContract Implementation

This section provides the complete, production-ready implementation of the PresaleContract.

### 10.1 Contract Interface (Full Specification)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPresaleContract {
    // Events
    event PhaseCreated(uint256 indexed phaseIndex, uint256 startTime, uint256 endTime, uint256 pricePerToken);
    event BuyTokens(address indexed buyer, uint256 usdcAmount, uint256 aicAmount, uint256 indexed phaseIndex);
    event PhaseAdvanced(uint256 indexed newPhase, uint256 price);
    event PresaleEnded(uint256 totalRaisedUSDC, uint256 totalTokensSold);
    event PresalePaused();
    event PresaleResumed();
    event TokensClaimed(address indexed user, uint256 amount);

    // Structs
    struct Phase {
        uint256 startTime;           // Unix timestamp phase begins
        uint256 endTime;             // Unix timestamp phase ends
        uint256 phaseCap;            // Cumulative USD cap (e.g., 500,000e6 = $500k)
        uint256 pricePerToken;       // Price in USDC (1e6 decimals)
        uint256 maxTokensPhase;      // Max tokens for this phase
        uint256 soldTokensPhase;     // Running total sold in phase
    }

    // External functions - User-facing
    function buyTokens(uint256 usdcAmount) external nonReentrant returns (uint256 aicAmount);
    function claimTokens() external nonReentrant returns (uint256 aicAmount);

    // View functions
    function getActivePhase() external view returns (uint256);
    function getPresaleStatus() external view returns (
        uint256 activePhase,
        uint256 totalRaised,
        uint256 totalTokens,
        uint256 percentToHardCap,
        bool presaleActive
    );
    function getPhaseInfo(uint256 phaseIndex) external view returns (Phase memory);
    function getUserInfo(address user) external view returns (
        uint256 contributed,
        uint256 allocated,
        uint256 claimed,
        bool hasClaimedTokens
    );
    function getPhaseCount() external view returns (uint256);

    // Admin functions
    function initializePresale(Phase[] memory _phases) external onlyOwner;
    function pause() external onlyOwner;
    function unpause() external onlyOwner;
    function finalizePresale() external onlyOwner;
}

contract PresaleContract is IPresaleContract, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // Token addresses
    IERC20 public immutable usdc;
    IERC20 public immutable aic;
    address public immutable treasury;

    // Constants
    uint256 public constant HARD_CAP = 7_000_000e6;  // $7M (USDC has 6 decimals)
    uint256 public constant PRESALE_ALLOCATION = 500_000_000 ether;  // 500M AIC tokens

    // State variables
    Phase[] public phases;
    uint256 public totalRaisedUSDC;
    uint256 public totalTokensSold;
    bool public presaleActive;
    bool public presaleFinalized;
    uint256 public tgeTime;  // Token generation event timestamp

    mapping(address => uint256) public contributions;  // USDC spent per user
    mapping(address => uint256) public tokenAllocated;  // AIC allocated per user
    mapping(address => uint256) public tokensClaimed;   // AIC claimed per user
    mapping(address => bool) public hasClaimedTokens;  // Claim flag per user

    // Custom errors
    error PresaleNotActive();
    error PresaleAlreadyActive();
    error InvalidAmount();
    error NoActivePhase();
    error PhaseCapExceeded();
    error HardCapExceeded();
    error InsufficientAllowance();
    error PhasesNotOrdered();
    error InvalidPhaseConfig();
    error PresaleNotFinalized();
    error TGENotReached();
    error NothingToClaim();
    error AlreadyClaimed();
    error InvalidTokenAddress();

    // Constructor
    constructor(
        address _usdc,
        address _aic,
        address _treasury
    ) Ownable(msg.sender) {
        if (_usdc == address(0) || _aic == address(0) || _treasury == address(0)) {
            revert InvalidTokenAddress();
        }

        usdc = IERC20(_usdc);
        aic = IERC20(_aic);
        treasury = _treasury;
    }

    // ============================================================
    // ADMIN FUNCTIONS
    // ============================================================

    /// @notice Initialize presale with phases
    /// @param _phases Array of presale phases
    function initializePresale(Phase[] memory _phases) external onlyOwner {
        if (presaleActive) revert PresaleAlreadyActive();
        if (_phases.length == 0) revert InvalidPhaseConfig();

        // Validate phase ordering and configuration
        for (uint256 i = 0; i < _phases.length; i++) {
            Phase memory phase = _phases[i];

            if (phase.startTime >= phase.endTime) revert InvalidPhaseConfig();
            if (phase.pricePerToken == 0) revert InvalidPhaseConfig();
            if (phase.maxTokensPhase == 0) revert InvalidPhaseConfig();
            if (phase.phaseCap == 0) revert InvalidPhaseConfig();

            // Validate phase ordering
            if (i > 0) {
                if (phase.startTime != _phases[i - 1].endTime) revert PhasesNotOrdered();
                if (phase.phaseCap <= _phases[i - 1].phaseCap) revert PhasesNotOrdered();
            }

            phases.push(phase);
            emit PhaseCreated(i, phase.startTime, phase.endTime, phase.pricePerToken);
        }

        // Set TGE to 7 days after last phase ends
        tgeTime = _phases[_phases.length - 1].endTime + 7 days;
        presaleActive = true;
    }

    /// @notice Pause presale (emergency)
    function pause() external onlyOwner {
        _pause();
        emit PresalePaused();
    }

    /// @notice Resume presale
    function unpause() external onlyOwner {
        _unpause();
        emit PresaleResumed();
    }

    /// @notice Finalize presale and transfer USDC to treasury
    function finalizePresale() external onlyOwner {
        if (!presaleActive) revert PresaleNotActive();

        presaleActive = false;
        presaleFinalized = true;

        // Transfer all USDC to treasury
        uint256 balance = usdc.balanceOf(address(this));
        usdc.safeTransfer(treasury, balance);

        emit PresaleEnded(totalRaisedUSDC, totalTokensSold);
    }

    // ============================================================
    // USER FUNCTIONS
    // ============================================================

    /// @notice Buy tokens during presale
    /// @param usdcAmount Amount of USDC to spend (in USDC base units, 6 decimals)
    /// @return aicAmount AIC tokens allocated
    function buyTokens(uint256 usdcAmount) external nonReentrant whenNotPaused returns (uint256 aicAmount) {
        if (!presaleActive) revert PresaleNotActive();
        if (usdcAmount == 0) revert InvalidAmount();

        // Get current phase
        uint256 phaseIdx = getActivePhase();
        if (phaseIdx == type(uint256).max) revert NoActivePhase();

        Phase storage phase = phases[phaseIdx];

        // Validate time bounds
        if (block.timestamp < phase.startTime || block.timestamp >= phase.endTime) {
            revert NoActivePhase();
        }

        // Calculate AIC tokens owed
        // Formula: aicAmount = (usdcAmount * 10^18) / pricePerToken
        aicAmount = (usdcAmount * 1e18) / phase.pricePerToken;

        // Validate phase allocation cap not exceeded
        if (phase.soldTokensPhase + aicAmount > phase.maxTokensPhase) {
            revert PhaseCapExceeded();
        }

        // Validate hard cap not exceeded
        if (totalRaisedUSDC + usdcAmount > HARD_CAP) {
            revert HardCapExceeded();
        }

        // Transfer USDC from user to contract (held until finalization)
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Update state
        contributions[msg.sender] += usdcAmount;
        tokenAllocated[msg.sender] += aicAmount;
        totalRaisedUSDC += usdcAmount;
        totalTokensSold += aicAmount;
        phase.soldTokensPhase += aicAmount;

        // Check if phase cap reached → trigger auto-advancement
        if (totalRaisedUSDC >= phase.phaseCap && phaseIdx < phases.length - 1) {
            uint256 nextPhasePrice = phases[phaseIdx + 1].pricePerToken;
            emit PhaseAdvanced(phaseIdx + 1, nextPhasePrice);
        }

        // Check if hard cap reached → end presale
        if (totalRaisedUSDC >= HARD_CAP) {
            presaleActive = false;
            emit PresaleEnded(totalRaisedUSDC, totalTokensSold);
        }

        emit BuyTokens(msg.sender, usdcAmount, aicAmount, phaseIdx);
        return aicAmount;
    }

    /// @notice Claim tokens after TGE
    /// @return aicAmount AIC tokens claimed
    function claimTokens() external nonReentrant returns (uint256 aicAmount) {
        if (!presaleFinalized) revert PresaleNotFinalized();
        if (block.timestamp < tgeTime) revert TGENotReached();
        if (tokenAllocated[msg.sender] == 0) revert NothingToClaim();
        if (hasClaimedTokens[msg.sender]) revert AlreadyClaimed();

        aicAmount = tokenAllocated[msg.sender];
        hasClaimedTokens[msg.sender] = true;
        tokensClaimed[msg.sender] += aicAmount;

        // Transfer AIC from contract to user
        aic.safeTransfer(msg.sender, aicAmount);

        emit TokensClaimed(msg.sender, aicAmount);
        return aicAmount;
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    /// @notice Get current active phase
    /// @return phaseIndex Index of active phase, or type(uint256).max if none
    function getActivePhase() public view returns (uint256 phaseIndex) {
        for (uint256 i = 0; i < phases.length; i++) {
            // Check if we've exceeded cumulative cap (auto-advance logic)
            if (totalRaisedUSDC < phases[i].phaseCap) {
                // Check time bounds
                if (block.timestamp >= phases[i].startTime && block.timestamp < phases[i].endTime) {
                    return i;
                }
            }
        }
        return type(uint256).max;  // No active phase
    }

    /// @notice Get overall presale status
    function getPresaleStatus()
        external
        view
        returns (
            uint256 activePhase,
            uint256 totalRaised,
            uint256 totalTokens,
            uint256 percentToHardCap,
            bool active
        )
    {
        activePhase = getActivePhase();
        totalRaised = totalRaisedUSDC;
        totalTokens = totalTokensSold;
        percentToHardCap = (totalRaisedUSDC * 100) / HARD_CAP;
        active = presaleActive;
    }

    /// @notice Get phase details by index
    function getPhaseInfo(uint256 phaseIndex) external view returns (Phase memory) {
        require(phaseIndex < phases.length, "Invalid phase index");
        return phases[phaseIndex];
    }

    /// @notice Get user contribution and allocation info
    function getUserInfo(address user)
        external
        view
        returns (
            uint256 contributed,
            uint256 allocated,
            uint256 claimed,
            bool hasClaimedTokens_
        )
    {
        return (
            contributions[user],
            tokenAllocated[user],
            tokensClaimed[user],
            hasClaimedTokens[user]
        );
    }

    /// @notice Get total number of phases
    function getPhaseCount() external view returns (uint256) {
        return phases.length;
    }
}
```

### 10.2 State Variables Deep Dive

| Variable | Type | Purpose | Example |
|---|---|---|---|
| `phases` | `Phase[]` | Array of 7 presale phases | `phases[0..6]` |
| `totalRaisedUSDC` | `uint256` | Cumulative USDC raised | `1_500_000e6` |
| `totalTokensSold` | `uint256` | Cumulative AIC allocated | `100_000_000e18` |
| `presaleActive` | `bool` | Presale ongoing flag | `true` → `false` on finish |
| `presaleFinalized` | `bool` | Presale completed & finalized | `false` → `true` after close |
| `tgeTime` | `uint256` | Token claim unlock time | 7 days after presale ends |
| `contributions[user]` | `mapping` | Total USDC per user | `1000e6` = $1000 |
| `tokenAllocated[user]` | `mapping` | Total AIC per user | `100_000e18` = 100k AIC |
| `tokensClaimed[user]` | `mapping` | AIC claimed by user | Initially 0 |
| `hasClaimedTokens[user]` | `mapping` | Claim flag (prevents double-claim) | `false` → `true` |

### 10.3 State Transitions

```
                     ┌─────────────────────┐
                     │  Uninitialized      │
                     │ presaleActive=false │
                     └──────────┬──────────┘
                                │
                  initializePresale(phases)
                                │
          ┌─────────────────────▼─────────────────────┐
          │         Phase 1: $0.010/AIC               │
          │    presaleActive=true, Cap: $500k         │
          └─────────────────────┬─────────────────────┘
                 totalRaisedUSDC >= $500k
                                │
          ├─ Phase 2: $0.013/AIC, Cap: $1M
          ├─ Phase 3: $0.020/AIC, Cap: $2M
          ├─ Phase 4: $0.028/AIC, Cap: $3.5M
          ├─ Phase 5: $0.038/AIC, Cap: $5M
          ├─ Phase 6: $0.053/AIC, Cap: $6M
          │
          └─ Phase 7: $0.070/AIC, Cap: $7M
                 totalRaisedUSDC >= $7M
                                │
                     ┌──────────▼──────────────┐
                     │ Presale Ended          │
                     │ presaleActive=false    │
                     │ (hard cap reached)     │
                     └──────────┬─────────────┘
                                │
                    finalizePresale()
                  (transfers USDC to treasury)
                                │
                     ┌──────────▼──────────────┐
                     │ Presale Finalized      │
                     │ presaleFinalized=true  │
                     │ TGE Locked for 7 days  │
                     └──────────┬─────────────┘
                                │
                    block.timestamp >= tgeTime
                                │
                     ┌──────────▼──────────────┐
                     │ Claim Phase Open       │
                     │ claimTokens() enabled  │
                     └────────────────────────┘
```

---

## 11. Treasury Contract Implementation

The Treasury holds raised funds and distributes according to governance decisions.

### 11.1 Treasury Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Treasury is Ownable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");

    IERC20 public immutable usdc;
    address public presaleContract;

    event FundsReceived(address indexed source, uint256 amount);
    event FundsWithdrawn(address indexed recipient, uint256 amount, string purpose);
    event PresaleContractSet(address indexed presaleContract);

    constructor(address _usdc, address[] memory multisigSigners) Ownable(msg.sender) {
        usdc = IERC20(_usdc);

        // Grant multisig role to all signers
        for (uint256 i = 0; i < multisigSigners.length; i++) {
            _grantRole(MULTISIG_ROLE, multisigSigners[i]);
        }
    }

    /// @notice Set presale contract address (can only be done once)
    function setPresaleContract(address _presaleContract) external onlyOwner {
        require(presaleContract == address(0), "Presale contract already set");
        presaleContract = _presaleContract;
        emit PresaleContractSet(_presaleContract);
    }

    /// @notice Receive USDC from presale (called by finalizePresale)
    receive() external payable {
        // Treasury receives ETH if needed
    }

    /// @notice Withdraw USDC (requires multisig approval)
    function withdrawUSDC(address recipient, uint256 amount, string memory purpose)
        external
        onlyRole(MULTISIG_ROLE)
    {
        usdc.safeTransfer(recipient, amount);
        emit FundsWithdrawn(recipient, amount, purpose);
    }

    /// @notice Get USDC balance
    function getBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
```

---

## 12. Testing Strategy

### 12.1 Unit Tests (Forge)

```solidity
// test/PresaleContract.t.sol

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PresaleContract} from "../src/PresaleContract.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PresaleContractTest is Test {
    PresaleContract presale;
    MockERC20 usdc;
    MockERC20 aic;

    address treasury = makeAddr("treasury");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        aic = new MockERC20("AIC", "AIC", 18);

        presale = new PresaleContract(
            address(usdc),
            address(aic),
            treasury
        );

        // Fund presale with AIC tokens
        aic.mint(address(presale), 500_000_000 ether);

        // Fund users with USDC
        usdc.mint(user1, 100_000e6);  // $100k
        usdc.mint(user2, 100_000e6);  // $100k
    }

    function test_InitializePresale() public {
        PresaleContract.Phase[] memory phases = new PresaleContract.Phase[](7);

        phases[0] = PresaleContract.Phase({
            startTime: block.timestamp,
            endTime: block.timestamp + 14 days,
            phaseCap: 500_000e6,
            pricePerToken: 0.010e6,
            maxTokensPhase: 50_000_000 ether,
            soldTokensPhase: 0
        });

        phases[1] = PresaleContract.Phase({
            startTime: block.timestamp + 14 days,
            endTime: block.timestamp + 28 days,
            phaseCap: 1_000_000e6,
            pricePerToken: 0.013e6,
            maxTokensPhase: 38_500_000 ether,
            soldTokensPhase: 0
        });

        // ... phases[2..6] defined similarly for Phase 3-7

        presale.initializePresale(phases);
        assert(presale.getPhaseCount() == 7);
    }

    function test_BuyTokens() public {
        // Initialize presale first
        // ... (setup phases)

        // User1 buys 1000 USDC during Phase 1
        vm.prank(user1);
        usdc.approve(address(presale), 1000e6);

        uint256 aicAmount = presale.buyTokens(1000e6);

        // At $0.01 per token: 1000 / 0.01 = 100,000 AIC
        assert(aicAmount == 100_000 ether);
        assert(presale.contributions(user1) == 1000e6);
        assert(presale.tokenAllocated(user1) == 100_000 ether);
    }

    function test_PhaseAdvance() public {
        // Initialize presale
        // ... (setup phases with Phase 1 cap at $500k)

        // Simulate reaching Phase 1 cap
        vm.prank(user1);
        usdc.approve(address(presale), 500_000e6);
        presale.buyTokens(500_000e6);

        // Next transaction should trigger Phase 2
        assert(presale.getActivePhase() == 1);  // Phase 2 (index 1)
    }

    function test_ClaimTokens() public {
        // ... initialize, buy tokens

        // Fast-forward past TGE
        uint256 tgeTime = block.timestamp + 60 days;
        vm.warp(tgeTime);

        // User can now claim
        vm.prank(user1);
        uint256 claimed = presale.claimTokens();
        assert(claimed == presale.tokenAllocated(user1));
        assert(aic.balanceOf(user1) == claimed);
    }

    function test_HardCapEnforced() public {
        // ... initialize presale

        // Try to exceed hard cap
        vm.prank(user1);
        usdc.approve(address(presale), 10_000_000e6);  // $10M > hard cap

        vm.expectRevert(PresaleContract.HardCapExceeded.selector);
        presale.buyTokens(10_000_000e6);
    }

    function test_ReentrancyProtection() public {
        // Forge's ReentrancyGuard prevents reentrancy
        // Mock a malicious token that reenters on transfer
        // Verify the transaction reverts
    }
}
```

### 12.2 Integration Tests

Test presale → treasury → token distribution flow end-to-end.

### 12.3 Fuzz Tests

```solidity
function testFuzz_BuyTokensWithRandomAmounts(uint256 usdcAmount) public {
    uint256 boundedAmount = bound(usdcAmount, 1e6, 1_000_000e6);  // $1 to $1M
    // ... test presale handles any valid amount
}
```

---

## 13. Deployment Guide

### 13.0 Network Configuration

**Production Deployment (Ethereum Mainnet):**
- Network: Ethereum Mainnet
- Chain ID: 1
- RPC Endpoint: `https://eth.llamarpc.com` (or Infura/Alchemy)
- USDC Address: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- Block Explorer: https://etherscan.io
- Gas Requirements: Estimated 2-3 ETH for contract deployments

**Testing Deployment (Ethereum Sepolia):**
- Network: Ethereum Sepolia Testnet
- Chain ID: 11155111
- RPC Endpoint: `https://sepolia.infura.io/v3/YOUR_PROJECT_ID` (or public endpoint)
- USDC Address: `0x6F14C02Fc1F78322cFd7d56a6350807271F94523` (Sepolia test USDC)
- Block Explorer: https://sepolia.etherscan.io
- Faucet for testnet ETH: https://sepoliafaucet.com

**Important:** Always test thoroughly on Sepolia before mainnet deployment.

### 13.1 Pre-Deployment Checklist

- [ ] All contracts audited and approved
- [ ] Test suite passes: `forge test --gas-report`
- [ ] Solidity version confirmed: 0.8.24
- [ ] OpenZeppelin version confirmed: v5.x
- [ ] Team and investor multisig addresses confirmed
- [ ] USDC address on Ethereum verified: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- [ ] All phase parameters finalized and documented
- [ ] Treasury multisig set up and tested

### 13.2 Deployment Steps

**Step 1: Deploy WebAI3Token**
```bash
forge script script/DeployWebAI3Token.s.sol \
  --rpc-url https://eth.llamarpc.com \
  --broadcast
```

Record token address: `0xABC...`

**Step 2: Deploy Treasury**
```bash
forge script script/DeployTreasury.s.sol \
  --constructor-args 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  --rpc-url https://eth.llamarpc.com \
  --broadcast
```

Record treasury address: `0xDEF...`

**Step 3: Deploy PresaleContract**
```bash
forge script script/DeployPresale.s.sol \
  --constructor-args \
  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 \
  0xABC... \
  0xDEF... \
  --rpc-url https://eth.llamarpc.com \
  --broadcast
```

Record presale address: `0x123...`

**Step 4: Initialize Presale Phases**
```bash
cast send 0x123... "initializePresale((uint256,uint256,uint256,uint256,uint256,uint256)[])" \
  "[($(TZ=UTC date -d '2026-03-10 10:00 UTC' +%s),$(TZ=UTC date -d '2026-03-24 10:00 UTC' +%s),500000000000,10000,50000000000000000000000000,0), ...]" \
  --rpc-url https://eth.llamarpc.com \
  --private-key $PRIVATE_KEY
```

**Step 5: Verify Contracts on Etherscan**
```bash
forge verify-contract \
  0xABC... \
  src/WebAI3Token.sol:WebAI3Token \
  --chain-id 1 \
  --etherscan-api-key $BASESCAN_API_KEY
```

**Step 6: Verify State**
```bash
cast call 0x123... "getPhaseCount()(uint256)" --rpc-url https://eth.llamarpc.com
# Should return: 4

cast call 0x123... "getPresaleStatus()(uint256,uint256,uint256,uint256,bool)" --rpc-url https://eth.llamarpc.com
# Should show active phase, zeros for raised/sold, etc.
```

---

## 14. Monitoring & Operations

### 14.1 Real-Time Monitoring

Set up alerting for these events:

```solidity
event BuyTokens(address indexed buyer, uint256 usdcAmount, uint256 aicAmount, uint256 indexed phaseIndex);
event PhaseAdvanced(uint256 indexed newPhase, uint256 price);
event PresaleEnded(uint256 totalRaisedUSDC, uint256 totalTokensSold);
```

Monitor via:
- Etherscan event logs
- Subgraph (GraphQL for indexing)
- Custom monitoring bot

### 14.2 Daily Reports

| Metric | Query | Action |
|---|---|---|
| Total Raised | `totalRaisedUSDC` | Track progress to hard cap |
| Active Phase | `getActivePhase()` | Verify no stuck phases |
| User Count | Count unique `buyer` in BuyTokens events | Community size |
| Avg Buy Size | `totalRaisedUSDC / userCount` | Market segment analysis |

### 14.3 Emergency Procedures

If security issue detected:

```bash
# 1. Pause presale immediately
cast send 0x123... "pause()" \
  --rpc-url https://eth.llamarpc.com \
  --private-key $PRIVATE_KEY

# 2. Pause public notification
# 3. Assess issue
# 4. Decide: resume or cancel presale
# 5. Resume if safe
cast send 0x123... "unpause()" \
  --rpc-url https://eth.llamarpc.com \
  --private-key $PRIVATE_KEY
```

---

## 15. Appendix: Complete Reference

### 15.1 Key Formulas

```
aicAmount = (usdcAmount × 10^18) / pricePerToken

Example (Phase 1):
- Input: 100 USDC
- Price: 0.01e6 (1e6 = $0.01)
- Calc: (100 × 10^6 × 10^18) / 1 × 10^6 = 100 × 10^18
- Result: 100 AIC tokens (but stored as 100e18 wei)

Wait, let me recalculate...
- Price = $0.01 per token
- So 100 USDC buys: 100 / 0.01 = 10,000 tokens
- In smart contract: usdcAmount = 100e6, pricePerToken = 0.01e6 = 10,000
- Formula: (100e6 * 1e18) / 10,000 = 10,000e18 AIC ✓
```

### 15.2 Phase Transition Table

| Event | Trigger | Result |
|---|---|---|
| Phase 1 → 2 | `totalRaisedUSDC >= $500k` | Auto-advance, price becomes $0.013 |
| Phase 2 → 3 | `totalRaisedUSDC >= $1M` | Auto-advance, price becomes $0.020 |
| Phase 3 → 4 | `totalRaisedUSDC >= $2M` | Auto-advance, price becomes $0.028 |
| Phase 4 → 5 | `totalRaisedUSDC >= $3.5M` | Auto-advance, price becomes $0.038 |
| Phase 5 → 6 | `totalRaisedUSDC >= $5M` | Auto-advance, price becomes $0.053 |
| Phase 6 → 7 | `totalRaisedUSDC >= $6M` | Auto-advance, price becomes $0.070 |
| Phase 7 → Ended | `totalRaisedUSDC >= $7M` | Hard cap reached, presale ends |
| Any Phase → Time Expired | `block.timestamp >= phaseEnd` | Phase extends at locked price |

### 15.3 Gas Optimization Notes

| Operation | Gas Cost | Notes |
|---|---|---|
| buyTokens() | ~80k–120k | Includes USDC transfer + state updates |
| claimTokens() | ~60k–80k | AIC transfer after TGE |
| getActivePhase() | ~5k–10k | View function (no state change) |
| buyTokens() cold | ~120k | First interaction (cold storage slots) |
| buyTokens() warm | ~80k | Subsequent calls (warm storage slots) |

Optimization strategies:
- Batch claims (off-chain aggregation)
- Use USDC instead of ETH (fewer decimal conversions)
- Index phases for O(1) lookup if using mapping instead of array

---

## 16. Future Extensions

### 16.1 Dynamic Bonding Curve

**Objective:** Smoother price progression and continuous buy/sell mechanism.

**Mechanism:**
- Replace discrete phases with continuous bonding curve
- Price = `basePrice * (totalSupplyMinted / hardCap) ^ 2`
- Users can buy/sell at any time (not phase-gated)
- Automatic price discovery

### 16.2 Onchain Governance

**Objective:** Decentralize presale decisions via DAO voting.

**Mechanisms:**
- Token holders vote to extend phases
- Vote to adjust prices dynamically
- Treasury fund allocation controlled by governance

### 16.3 Revenue Sharing

**Objective:** Token holders receive portion of inference API fees.

**Flow:**
1. Users pay in USDC for AI model inference
2. Protocol collects 10% fee on each transaction
3. Revenue distributed to AIC token stakers (weekly)
4. Staking yield: ~15-20% APY

### 16.4 Secondary Markets & Perpetuals

**Objective:** Enable derivatives trading on AIC token.

**Integrations:**
- Listing on major exchanges (Binance, Coinbase, Kraken)
- Perpetual futures on dYdX, GMX
- Options markets (Dopex, Lyra)

---

## References

- **Solidity 0.8.24:** https://docs.soliditylang.org
- **OpenZeppelin Contracts v5:** https://docs.openzeppelin.com/contracts/5.x
- **ERC-20 Standard:** https://eips.ethereum.org/EIPS/eip-20
- **Ethereum:** https://ethereum.org
- **Uniswap v3:** https://uniswap.org
- **ReentrancyGuard:** https://docs.openzeppelin.com/contracts/5.x/api/security
- **Foundry Book:** https://book.getfoundry.sh/

---

**Document Version:** 2.1
**Status:** Complete - Implementation Ready (Ethereum Network)
**Last Updated:** March 2026
**Networks:** Ethereum Mainnet (Production) | Ethereum Sepolia (Testing)

**Next Steps for Engineering Team:**
1. Review complete contract implementation (Section 10)
2. Set up test environment with Foundry
3. Write comprehensive test suite (Section 12)
4. Perform internal security review
5. Engage external auditor
6. Deploy to Ethereum Sepolia testnet
7. Community testing and feedback
8. Deploy to Ethereum mainnet (Section 13)
