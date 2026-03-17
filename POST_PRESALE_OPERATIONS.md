# Post-Presale Operations

Technical reference for all on-chain actions following the end of the WebAI3 presale. Covers actors, preconditions, exact contract calls, state transitions, and timing constraints.

---

## Actors

| Actor | Description | Required Role |
|---|---|---|
| **Anyone** | Any Ethereum address — no role required | — |
| **Admin** | Deployer wallet holding `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` |
| **Liquidity Operator** | Executes DEX liquidity provision | `LIQUIDITY_OPERATOR_ROLE` on `LiquidityVault` |
| **Dev Operator** | Withdraws dev runway funds | `DEV_OPERATOR_ROLE` on `DevRunwayVault` |
| **Team Operator** | Withdraws team stream funds | `TEAM_OPERATOR_ROLE` on `TeamStreamVault` |
| **Marketing Operator** | Queues and executes marketing withdrawals | `MARKETING_OPERATOR_ROLE` on `MarketingVault` |
| **Buyer** | Presale participant claiming AIC tokens | — |

---

## Contract Addresses (Sepolia)

| Contract | Address |
|---|---|
| `WebAI3Presale` | `0x22Eec638a99ec9F8ffad231666baf9a9304CeF96` |
| `PresaleVault` | `0x220663B010DB4E6c3Da750B70Ee84B8BBa0F6C64` |
| `LiquidityVault` | `0x78DD71d73a59D376BB4dDC1ebcBdC9bA26EED19E` |
| `DevRunwayVault` | `0x61A6207526ab7231431da9EfD155C91d2De0aefA` |
| `TeamStreamVault` | `0xB60Ce11B006307d84c44ff4FA0E81E05B5231C6b` |
| `MarketingVault` | `0x841e3Cb3b19D150C31a509CC77CB4264Cc2C4685` |
| `ClaimModule` | `0x7EFC15670baD86dA4c39b86a46A90DEEce8850A3` |
| `WebAI3Token (AIC)` | `0xE375BC84dcd834a0662Aff41e8e18d1f2A907F18` |

**Key timestamps (Sepolia deployment):**

| Event | Unix timestamp | Human-readable (UTC) |
|---|---|---|
| Presale start | `1773643234` | ~Mar 16 2026 |
| Presale end | `1784011234` | ~Jul 14 2026 |
| TGE | `1784097634` | ~Jul 15 2026 |

---

## Presale End Triggers

The presale ends when **either** condition is met:

```
block.timestamp >= PRESALE_END_TIMESTAMP   // time-based
OR
totalRaisedUSDC >= HARD_CAP (7,000,000 USDC)  // hard cap reached
```

Once either condition is true, `WebAI3Presale.isFinalizable()` returns `true` and `buyTokens()` will revert. No new purchases are possible.

---

## Phase 1 — Finalization

**Who calls it:** Anyone (permissionless)
**Precondition:** `isFinalizable() == true`
**Can only happen once:** `presaleFinalized` flag prevents re-entry

### Call

```
WebAI3Presale.finalizePresale()
```

### Execution trace

```
WebAI3Presale.finalizePresale()
  ├─ assert: !presaleFinalized
  ├─ assert: isFinalizable() == true
  ├─ presaleFinalized = true
  ├─ if (_pauseActive): _liftPause(forced=true)   // auto-clears any active pause
  ├─ finalizedAt = block.timestamp
  ├─ PresaleVault.onPresaleFinalized(finalizedAt)
  │     ├─ LiquidityVault.onPresaleFinalized(finalizedAt)
  │     │     ├─ presaleFinalized = true
  │     │     └─ finalizedAt = finalizedAt          // starts the 7-day operator window
  │     └─ MarketingVault.onPresaleFinalized(finalizedAt)
  │           ├─ presaleFinalized = true
  │           └─ finalizedAt = finalizedAt          // unlocks queueWithdrawal
  └─ emit PresaleFinalized(finalizedAt, totalRaisedUSDC, totalAllocatedTokens)
```

### State after

| Contract | State change |
|---|---|
| `WebAI3Presale` | `presaleFinalized = true`, `lifecycle = Finalized` |
| `LiquidityVault` | `presaleFinalized = true`, `finalizedAt` set — operator window starts |
| `MarketingVault` | `presaleFinalized = true`, `finalizedAt` set — withdrawals unlocked |

> **Note:** `DevRunwayVault` and `TeamStreamVault` do not receive a finalization callback. Their streams are tied to `presaleStartTimestamp`, which is fixed at deployment, so they are already streaming from day one of the presale regardless of finalization.

---

## Phase 2 — Liquidity Provisioning

This is the **critical gate** for claims. `ClaimModule.enableClaims()` cannot be called until liquidity is provisioned. Two paths exist with a strict timing boundary.

### Path A — Primary (operator-controlled, within 7 days)

**Who calls it:** Liquidity Operator
**Window:** `finalizedAt < block.timestamp <= finalizedAt + 7 days`

```
LiquidityVault.provideLiquidity()
  ├─ assert: LIQUIDITY_OPERATOR_ROLE
  ├─ assert: presaleFinalized == true
  ├─ assert: liquidityProvisioned == false
  ├─ assert: block.timestamp <= finalizedAt + 7 days
  ├─ usdcAmount = usdc.balanceOf(address(this))   // entire vault balance
  ├─ usdc.safeTransfer(liquidityRecipient, usdcAmount)
  ├─ liquidityProvisioned = true
  ├─ totalProvisionedUSDC += usdcAmount
  └─ emit LiquidityProvisionedEvent(caller, usdcAmount, viaFallback=false)
```

### Path B — Fallback (permissionless, after 7 days)

**Who calls it:** Anyone
**Window:** `block.timestamp > finalizedAt + 7 days`
**Purpose:** Prevents permanent lock if the operator key is unavailable

```
LiquidityVault.provideLiquidityFallback()
  ├─ assert: presaleFinalized == true
  ├─ assert: liquidityProvisioned == false
  ├─ assert: block.timestamp > finalizedAt + 7 days
  ├─ usdcAmount = usdc.balanceOf(address(this))
  ├─ usdc.safeTransfer(liquidityRecipient, usdcAmount)
  ├─ liquidityProvisioned = true
  ├─ totalProvisionedUSDC += usdcAmount
  └─ emit LiquidityProvisionedEvent(caller, usdcAmount, viaFallback=true)
```

### State after

| Contract | State change |
|---|---|
| `LiquidityVault` | `liquidityProvisioned = true`, USDC transferred to `liquidityRecipient` |
| `WebAI3Presale` | `liquidityProvisioned()` now returns `true` (reads through to `LiquidityVault`) |

---

## Phase 3 — Enable Claims

**Who calls it:** Anyone (permissionless)
**Preconditions (both required):**
- `WebAI3Presale.presaleFinalized() == true`
- `WebAI3Presale.liquidityProvisioned() == true` (i.e., Phase 2 must be complete)

```
ClaimModule.enableClaims()
  ├─ assert: !claimsEnabled
  ├─ assert: presale != address(0)
  ├─ assert: presale.presaleFinalized() == true
  ├─ assert: presale.liquidityProvisioned() == true
  ├─ claimsEnabled = true
  └─ emit ClaimsEnabled(block.timestamp)
```

### State after

| Contract | State change |
|---|---|
| `ClaimModule` | `claimsEnabled = true` — buyers may now call `claim()` |

---

## Phase 4 — Token Claims (Buyers)

**Who calls it:** Any buyer (their wallet directly)
**Precondition:** `claimsEnabled == true` and `block.timestamp >= tgeTimestamp`

### Vesting schedule

| Checkpoint | Timestamp | Cumulative vested |
|---|---|---|
| TGE | `tgeTimestamp` (= presale end + 1 day) | **30%** |
| TGE + 90 days | `tgeTimestamp + 90 days` | **65%** |
| TGE + 180 days | `tgeTimestamp + 180 days` | **100%** |

### Call

```
ClaimModule.claim()
  ├─ assert: claimsEnabled == true
  ├─ assert: presale.presaleFinalized() == true
  ├─ assert: presale.liquidityProvisioned() == true
  ├─ amount = claimableAmount(msg.sender)
  │     ├─ allocation = totalAllocation[msg.sender]
  │     ├─ vested = allocation * vestedBps() / 10_000
  │     └─ return vested - totalClaimed[msg.sender]
  ├─ assert: amount > 0
  ├─ totalClaimed[msg.sender] += amount
  ├─ aicToken.safeTransfer(msg.sender, amount)
  └─ emit TokensClaimed(msg.sender, amount, totalClaimed[msg.sender])
```

Buyers can call `claim()` multiple times — each call transfers only the newly vested and unclaimed portion. The contract tracks `totalClaimed[buyer]` to prevent double-claiming.

---

## Phase 5 — Vault Withdrawals (Operators)

These three vaults operate independently of each other and of the claim pipeline. They can be withdrawn from at any time after their respective conditions are met.

### 5A. Dev Runway Vault

**Who calls it:** Dev Operator
**Available from:** `presaleStartTimestamp` (streams from presale start, not finalization)
**Stream duration:** 180 days
**Max budget:** 1,050,000 USDC (15% of $7M hard cap, capped to actual deposited amount)

```
DevRunwayVault.withdraw(amount)
  ├─ assert: DEV_OPERATOR_ROLE
  ├─ available = withdrawableDev()
  │     ├─ elapsed = block.timestamp - presaleStartTimestamp
  │     ├─ streamed = min(DEV_MAX_BUDGET * elapsed / 180days, totalDeposited)
  │     └─ return streamed - totalWithdrawn
  ├─ assert: amount <= available
  ├─ totalWithdrawn += amount
  ├─ usdc.safeTransfer(beneficiary, amount)
  └─ emit DevWithdrawn(caller, amount, beneficiary)
```

**Formula:**
`withdrawable = min((1,050,000 USDC × elapsed_seconds) / 15,552,000, totalDeposited) − totalWithdrawn`

### 5B. Team Stream Vault

**Who calls it:** Team Operator
**Stream duration:** 365 days from `presaleStartTimestamp`
**Proportional:** based on actual deposited amount, not a fixed budget

```
TeamStreamVault.withdraw(amount)
  ├─ assert: TEAM_OPERATOR_ROLE
  ├─ available = withdrawableAmount()
  │     ├─ elapsed = block.timestamp - streamStartTimestamp
  │     ├─ streamed = min(totalDeposited * elapsed / streamDuration, totalDeposited)
  │     └─ return streamed - totalWithdrawn
  ├─ assert: amount <= available
  ├─ totalWithdrawn += amount
  ├─ usdc.safeTransfer(beneficiary, amount)
  └─ emit TeamWithdrawn(caller, amount, beneficiary)
```

**Formula:**
`withdrawable = (totalDeposited × elapsed_seconds) / 31,536,000 − totalWithdrawn`

### 5C. Marketing Vault

**Who calls it:** Marketing Operator
**Available from:** After `finalizePresale()` is called
**Timelock:** 2-day delay between queue and execution
**No streaming** — full balance available immediately post-finalization, subject to the timelock

#### Step 1: Queue

```
MarketingVault.queueWithdrawal(amount)
  ├─ assert: MARKETING_OPERATOR_ROLE
  ├─ assert: presaleFinalized == true
  ├─ assert: pendingWithdrawalAmount == 0    // no existing queued withdrawal
  ├─ assert: amount <= availableBalance()    // totalDeposited - totalWithdrawn
  ├─ pendingWithdrawalAmount = amount
  ├─ pendingWithdrawalReadyAt = block.timestamp + withdrawalDelay (2 days)
  └─ emit MarketingWithdrawalQueued(caller, amount, readyAt, beneficiary)
```

#### Step 2: Wait 2 days

#### Step 3: Execute

```
MarketingVault.executeWithdrawal()
  ├─ assert: MARKETING_OPERATOR_ROLE
  ├─ assert: pendingWithdrawalAmount > 0
  ├─ assert: block.timestamp >= pendingWithdrawalReadyAt
  ├─ assert: amount <= availableBalance()
  ├─ pendingWithdrawalAmount = 0
  ├─ pendingWithdrawalReadyAt = 0
  ├─ totalWithdrawn += amount
  ├─ usdc.safeTransfer(beneficiary, amount)
  └─ emit MarketingWithdrawalExecuted(caller, amount, beneficiary)
```

#### Optional: Cancel before execution

```
MarketingVault.cancelQueuedWithdrawal()
  ├─ assert: MARKETING_OPERATOR_ROLE
  ├─ assert: pendingWithdrawalAmount > 0
  ├─ pendingWithdrawalAmount = 0
  ├─ pendingWithdrawalReadyAt = 0
  └─ emit MarketingWithdrawalCancelled(caller, previousAmount)
```

---

## Timeline Overview

```
PRESALE_START_TIMESTAMP
│
│  [Presale active — buyers call buyTokens()]
│  [Dev stream begins accumulating from this point]
│  [Team stream begins accumulating from this point]
│
PRESALE_END_TIMESTAMP  (or HARD_CAP hit)
│
├─ T+0    Anyone calls finalizePresale()
│            └─ LiquidityVault.finalizedAt set → operator window opens
│            └─ MarketingVault.presaleFinalized = true → queue unlocked
│
├─ T+0 to T+7d    [LIQUIDITY_OPERATOR window]
│            └─ LiquidityVault.provideLiquidity()   ← preferred path
│
├─ T+7d+   Anyone may call LiquidityVault.provideLiquidityFallback()
│
│  [Once liquidity provisioned:]
├─ Anyone calls ClaimModule.enableClaims()
│
TGE (= PRESALE_END + 1 day)
├─ Buyers can claim 30% of allocation
│
TGE + 90 days
├─ Buyers can claim 65% of allocation (cumulative)
│
TGE + 180 days
└─ Buyers can claim 100% of allocation
```

---

## Dependency Graph

```
finalizePresale()                          [permissionless]
       │
       ├──────────────────────────────────┐
       ▼                                  ▼
LiquidityVault                     MarketingVault
.onPresaleFinalized()              .onPresaleFinalized()
       │                                  │
       │ (operator or fallback)           │ (operator + 2-day timelock)
       ▼                                  ▼
.provideLiquidity()            .queueWithdrawal()
       │                       .executeWithdrawal()
       │ liquidityProvisioned = true
       │
       ▼
ClaimModule.enableClaims()             [permissionless]
       │
       ▼
ClaimModule.claim()                    [per buyer, per vesting checkpoint]


— independent streams (no dependency on finalization) —

DevRunwayVault.withdraw()              [streams from presaleStartTimestamp]
TeamStreamVault.withdraw()             [streams from presaleStartTimestamp]
```

---

## Critical Path Summary

For buyers to claim tokens, **three transactions must happen in sequence**:

```
1. finalizePresale()           — Anyone, after end condition
2. provideLiquidity()          — Liquidity Operator (or fallback after 7 days)
3. enableClaims()              — Anyone, after 1 and 2
```

After step 3, buyers call `claim()` freely at any time, with amounts unlocking at TGE, TGE+90d, and TGE+180d.

The vault withdrawals (Dev, Team, Marketing) are independent of this path and can proceed as soon as their respective conditions are met.

---

## Error Reference

| Error | Contract | Meaning |
|---|---|---|
| `PresaleAlreadyFinalized` | Presale | `finalizePresale()` called twice |
| `PresaleNotFinalizable` | Presale | End condition not yet met |
| `PresaleNotFinalized` | LiquidityVault, ClaimModule | Action requires finalization first |
| `LiquidityAlreadyProvisioned` | LiquidityVault | Provision called twice |
| `LiquidityWindowExpired` | LiquidityVault | Primary path called after 7-day window |
| `LiquidityFallbackNotAvailable` | LiquidityVault | Fallback called within operator window |
| `LiquidityNotProvisioned` | ClaimModule | `enableClaims()` called before liquidity |
| `AlreadyConfigured` | ClaimModule | `enableClaims()` called twice |
| `ClaimsNotEnabled` | ClaimModule | `claim()` before `enableClaims()` |
| `NothingClaimable` | ClaimModule | No vested and unclaimed balance |
| `MarketingLocked` | MarketingVault | `queueWithdrawal()` before finalization |
| `TimelockNotReady` | MarketingVault | `executeWithdrawal()` before timelock expires |
| `NoQueuedWithdrawal` | MarketingVault | Execute or cancel with no pending queue |
| `WithdrawalExceedsLimit` | Dev/Team/MarketingVault | Requested amount exceeds available |
