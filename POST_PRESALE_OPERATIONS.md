# What Happens After the WebAI3 Presale Ends

This document explains every action that needs to happen once the presale is over — who does it, why they do it, and what changes on-chain as a result. It is written for everyone involved: team operators, the liquidity team, the marketing lead, presale participants, and technically curious observers.

---

## The Big Picture

When the presale ends, the protocol doesn't automatically "unlock." A small sequence of actions needs to happen in order before token buyers can claim their AIC. Think of it like a relay race — each leg hands off to the next.

Here's the full picture at a glance:

```
PRESALE ENDS
     │
     ▼
① Anyone calls finalizePresale()
   → Sets the clock for everything else
     │
     ├──────────────────────────────────────────────┐
     ▼                                              ▼
② Liquidity Operator seeds the DEX pool      Marketing Operator can now
   (must happen within 7 days)                queue withdrawals
     │
     ▼
③ Anyone calls enableClaims()
   → The token claim window is now open
     │
     ▼
④ Token buyers claim their AIC
   (30% at TGE, 65% at TGE+90d, 100% at TGE+180d)


— Running in parallel from Presale Start —

⑤ Dev Runway streams over 180 days
⑥ Team stream runs over 365 days
```

The critical path for buyers is steps ①②③. Steps ⑤ and ⑥ run independently.

---

## Contract Addresses (Sepolia Testnet)

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

**Key dates (Sepolia deployment):**

| Event | Timestamp | Date (UTC) |
|---|---|---|
| Presale start | `1773643234` | ~Mar 16, 2026 |
| Presale end | `1784011234` | ~Jul 14, 2026 |
| TGE | `1784097634` | ~Jul 15, 2026 |

---

## Who's Who

Before getting into the steps, here's a clear picture of each person or group involved and what role they play.

### Presale Participants (Buyers)

These are the people who contributed USDC during the presale in exchange for an AIC allocation. Their tokens don't arrive all at once — they vest over time starting at TGE (Token Generation Event). Buyers don't need to do anything until claims are enabled; once they are, buyers interact directly with the `ClaimModule` contract to pull their tokens.

**What they care about:** When can I get my tokens? How much can I claim right now?

---

### The Admin

The wallet that deployed the contracts and holds `DEFAULT_ADMIN_ROLE`. The admin is not required to take any action in the post-presale flow — the critical steps are either permissionless (callable by anyone) or delegated to specific operator wallets.

**What they care about:** Everything is set up correctly before the presale ends.

---

### The Liquidity Operator

This is the most time-sensitive role after finalization. The Liquidity Operator holds `LIQUIDITY_OPERATOR_ROLE` on the `LiquidityVault` and is responsible for taking the USDC held in the vault and providing it as liquidity on a DEX. They have a **7-day window** after finalization to do this. If they miss the window, anyone can trigger the fallback path instead.

**What they care about:** Getting liquidity seeded before the window expires, which unblocks token claims for all buyers.

---

### The Dev Operator

Holds `DEV_OPERATOR_ROLE` on `DevRunwayVault`. This is whoever manages the day-to-day engineering budget for the WebAI3 project. The vault streams USDC continuously over 180 days starting from when the presale began — not from finalization. The operator calls `withdraw()` whenever they need to pull available runway funds.

**What they care about:** Accessing the development budget as it unlocks over time.

---

### The Team Operator

Holds `TEAM_OPERATOR_ROLE` on `TeamStreamVault`. Similar to the Dev Operator, but for team compensation. This vault also streams from the presale start date, over a longer 365-day period. The operator calls `withdraw()` to pull available funds.

**What they care about:** Accessing team allocation as it vests.

---

### The Marketing Operator

Holds `MARKETING_OPERATOR_ROLE` on `MarketingVault`. Unlike the streaming vaults, marketing funds are available in full after finalization — but with a 2-day timelock. The operator must queue a withdrawal first, then wait 2 days, then execute it. This design prevents instant large transfers and allows time for intervention if something goes wrong.

**What they care about:** Funding marketing campaigns after the presale closes.

---

## Step 1 — Finalize the Presale

**Who does it:** Anyone — no special wallet required.\
**When:** After the presale ends (either time-based or hard cap reached).\
**One-time:** This can only happen once. The `presaleFinalized` flag prevents it from running again.

### Why this step exists

The presale contract needs an explicit signal that the fundraise is over. This is the trigger that sets timestamps and unlocks downstream actions. It also automatically clears any active emergency pause if one was in place.

### How to call it

```
WebAI3Presale.finalizePresale()
```

The presale ends when either condition is true:
- The current time has passed `PRESALE_END_TIMESTAMP`
- Total USDC raised has hit the $7,000,000 hard cap

You can check readiness by calling `WebAI3Presale.isFinalizable()` — if it returns `true`, the call will succeed.

### What happens under the hood

```
WebAI3Presale.finalizePresale()
  ├─ Confirms presale hasn't been finalized yet
  ├─ Confirms end condition is met
  ├─ Sets presaleFinalized = true
  ├─ Clears any active emergency pause (if one was running)
  ├─ Records finalizedAt = current timestamp
  ├─ Notifies LiquidityVault
  │     └─ LiquidityVault records finalizedAt → starts the 7-day operator window
  └─ Notifies MarketingVault
        └─ MarketingVault unlocks queueWithdrawal()
```

### State after this step

| Contract | What changed |
|---|---|
| `WebAI3Presale` | `presaleFinalized = true` |
| `LiquidityVault` | Operator window clock starts |
| `MarketingVault` | Withdrawal queuing is now unlocked |

> **Note on Dev and Team Vaults:** Neither vault receives a finalization callback. That's intentional — their streams are tied to `presaleStartTimestamp`, which was set at deployment. They've been accumulating unlockable funds since the presale opened, regardless of whether finalization has happened.

---

## Step 2 — Provide Liquidity

This is the **gating step** for everything buyers care about. Claims cannot be enabled until liquidity is provisioned.

### Path A — The Normal Path (Liquidity Operator, within 7 days)

**Who does it:** The Liquidity Operator.\
**Window:** From finalization until exactly 7 days after.\
**Why this window exists:** It gives the operator a reliable deadline. If they don't act, the protocol doesn't get stuck — anyone can use the fallback.

The Liquidity Operator calls:

```
LiquidityVault.provideLiquidity()
```

This transfers the entire USDC balance of the vault to the `liquidityRecipient` address (the DEX or liquidity provisioning contract). The full balance is sent in one transaction — no partial amounts.

```
LiquidityVault.provideLiquidity()
  ├─ Confirms caller has LIQUIDITY_OPERATOR_ROLE
  ├─ Confirms presale is finalized
  ├─ Confirms liquidity hasn't already been provided
  ├─ Confirms we're still within the 7-day window
  ├─ Reads entire USDC balance of the vault
  ├─ Transfers all USDC to liquidityRecipient
  └─ Sets liquidityProvisioned = true
```

---

### Path B — The Fallback (Anyone, after 7 days)

**Who does it:** Anyone.\
**When:** More than 7 days after finalization.\
**Why this exists:** Insurance against an unavailable or lost operator key. The protocol should never be permanently blocked because one wallet went offline.

```
LiquidityVault.provideLiquidityFallback()
```

Works identically to Path A, except it's available after the operator window and has no role restriction.

---

### State after this step

| Contract | What changed |
|---|---|
| `LiquidityVault` | `liquidityProvisioned = true`, USDC transferred out |
| `WebAI3Presale` | `liquidityProvisioned()` now returns `true` |

---

## Step 3 — Enable Claims

**Who does it:** Anyone — no special wallet required.\
**When:** After both Step 1 and Step 2 are complete.

This is a simple permissionless call that opens the claim window for all buyers.

```
ClaimModule.enableClaims()
```

The contract checks that both preconditions are met before proceeding:

```
ClaimModule.enableClaims()
  ├─ Confirms claims haven't already been enabled
  ├─ Confirms presale is finalized (Step 1 done)
  ├─ Confirms liquidity is provisioned (Step 2 done)
  └─ Sets claimsEnabled = true
```

Once this transaction lands, buyers can start claiming.

---

## Step 4 — Token Claims (Buyers)

**Who does it:** Each buyer, from their own wallet.\
**When:** After Step 3, at any time — but actual claimable amounts depend on how much time has passed since TGE.

### Vesting Schedule

AIC tokens don't all unlock at once. They release in three tranches:

| When | How much unlocks | Example: 10,000 AIC allocation |
|---|---|---|
| TGE (Jul 15, 2026) | 30% | 3,000 AIC claimable |
| TGE + 90 days | 65% cumulative | 3,500 more AIC (6,500 total) |
| TGE + 180 days | 100% cumulative | 3,500 more AIC (10,000 total) |

There's no need to claim at exactly the right moment — the contract tracks what's been claimed and only releases what's newly vested and not yet taken. Buyers can claim once per tranche or let multiple tranches accumulate and claim them together.

### How to claim

```
ClaimModule.claim()
```

The contract calculates the claimable amount automatically:

```
ClaimModule.claim()
  ├─ Confirms claims are enabled
  ├─ Confirms presale is finalized and liquidity is provisioned
  ├─ Calculates: (allocation × vested%) − already claimed
  ├─ Transfers the claimable amount of AIC to the buyer
  └─ Updates the buyer's claimed balance
```

Buyers can call this as many times as they like. Each call only transfers tokens that are newly vested since the last claim.

---

## Step 5 — Vault Withdrawals (Operators)

These three vaults operate completely independently from the claim pipeline. Operators don't need to wait for finalization (except Marketing) and can withdraw on their own schedule.

---

### 5A — Dev Runway Vault

**Operator:** Dev Operator (holds `DEV_OPERATOR_ROLE`)\
**Total budget:** Up to 1,050,000 USDC (15% of the $7M hard cap)\
**Stream:** Unlocks linearly over 180 days starting from presale start

The dev stream started the moment the presale opened. By the time the presale ends, a portion has already accumulated and is ready to withdraw.

**Formula:**
```
Available = min(1,050,000 USDC × days_elapsed / 180, total_deposited) − already_withdrawn
```

**How to withdraw:**

```
DevRunwayVault.withdraw(amount)
  ├─ Confirms caller has DEV_OPERATOR_ROLE
  ├─ Calculates currently available based on stream progress
  ├─ Confirms requested amount ≤ available
  └─ Transfers USDC to the beneficiary address
```

The operator can withdraw any amount up to what's currently available, as often as needed.

---

### 5B — Team Stream Vault

**Operator:** Team Operator (holds `TEAM_OPERATOR_ROLE`)\
**Total budget:** Whatever was deposited (10% of raised USDC, proportional to actual raise)\
**Stream:** Unlocks proportionally over 365 days starting from presale start

Same mechanics as the Dev Vault but over a longer period. Team allocation releases more gradually over a full year.

**Formula:**
```
Available = (total_deposited × days_elapsed / 365) − already_withdrawn
```

**How to withdraw:**

```
TeamStreamVault.withdraw(amount)
  ├─ Confirms caller has TEAM_OPERATOR_ROLE
  ├─ Calculates currently available
  ├─ Confirms requested amount ≤ available
  └─ Transfers USDC to the beneficiary address
```

---

### 5C — Marketing Vault

**Operator:** Marketing Operator (holds `MARKETING_OPERATOR_ROLE`)\
**Available from:** After `finalizePresale()` is called\
**Mechanism:** Full balance available, but requires a 2-day timelock

Unlike the streaming vaults, the marketing budget is fully available post-finalization. However, all withdrawals require a 2-day waiting period between queuing and execution. This is a deliberate safety mechanism — it gives time to catch and cancel a mistaken or unauthorized withdrawal before funds leave.

**Step 1 — Queue the withdrawal:**

```
MarketingVault.queueWithdrawal(amount)
  ├─ Confirms caller has MARKETING_OPERATOR_ROLE
  ├─ Confirms presale is finalized
  ├─ Confirms no other withdrawal is already queued
  ├─ Confirms amount ≤ remaining balance
  └─ Records the pending withdrawal and sets readyAt = now + 2 days
```

**Step 2 — Wait 2 days.**

**Step 3 — Execute:**

```
MarketingVault.executeWithdrawal()
  ├─ Confirms caller has MARKETING_OPERATOR_ROLE
  ├─ Confirms a withdrawal is queued
  ├─ Confirms the 2-day wait is over
  └─ Transfers USDC to the beneficiary address
```

**Optional — Cancel before execution:**

If the queued amount was a mistake, the operator can cancel it before the 2 days are up:

```
MarketingVault.cancelQueuedWithdrawal()
  ├─ Confirms caller has MARKETING_OPERATOR_ROLE
  ├─ Confirms a withdrawal is queued
  └─ Clears the pending withdrawal (no funds moved)
```

---

## Full Timeline

```
PRESALE_START (Mar 16, 2026)
│
│   Buyers call buyTokens() throughout this period
│   Dev runway begins streaming from this point
│   Team stream begins streaming from this point
│
PRESALE_END (Jul 14, 2026) — or HARD_CAP hit
│
├─ Day 0     Anyone calls finalizePresale()
│               LiquidityVault operator window opens
│               MarketingVault queue unlocked
│
├─ Day 0–7   LIQUIDITY_OPERATOR calls provideLiquidity()
│               → preferred path
│
├─ Day 7+    If operator missed window:
│               Anyone can call provideLiquidityFallback()
│
│   Once liquidity provisioned:
├─ ─────     Anyone calls enableClaims()
│
TGE (Jul 15, 2026)
├─ Buyers can claim 30% of their allocation
│
TGE + 90 days (Oct 13, 2026)
├─ Buyers can claim 65% cumulative (35% more)
│
TGE + 180 days (Jan 11, 2027)
└─ Buyers can claim 100% cumulative (35% more)
```

---

## Stakeholder Checklist

### Liquidity Operator — Time-Critical
- [ ] Monitor for `PresaleFinalized` event on `WebAI3Presale`
- [ ] Call `LiquidityVault.provideLiquidity()` within 7 days of finalization
- [ ] Confirm `liquidityProvisioned = true` on-chain

### Anyone (can help unblock the chain)
- [ ] Call `WebAI3Presale.finalizePresale()` once presale end condition is met
- [ ] Call `ClaimModule.enableClaims()` after Steps 1 and 2 are complete
- [ ] Call `LiquidityVault.provideLiquidityFallback()` if operator missed the 7-day window

### Dev Operator — Ongoing
- [ ] Call `DevRunwayVault.withdraw(amount)` whenever runway funds are needed
- [ ] Check `withdrawableDev()` to see currently available amount

### Team Operator — Ongoing
- [ ] Call `TeamStreamVault.withdraw(amount)` as team allocation unlocks
- [ ] Check `withdrawableAmount()` to see currently available amount

### Marketing Operator — Post-Finalization
- [ ] Call `MarketingVault.queueWithdrawal(amount)` after finalization
- [ ] Wait 2 days
- [ ] Call `MarketingVault.executeWithdrawal()` to release funds
- [ ] Use `cancelQueuedWithdrawal()` if the queued amount needs to be changed

### Token Buyers — After Claims Enabled
- [ ] Wait for `ClaimsEnabled` event on `ClaimModule`
- [ ] Call `ClaimModule.claim()` at TGE, TGE+90d, and TGE+180d (or any time after each)
- [ ] Check `claimableAmount(address)` to see what's currently available

---

## What Could Go Wrong

| Situation | What happens |
|---|---|
| Liquidity Operator goes offline | After 7 days, anyone can call `provideLiquidityFallback()` — the protocol is never permanently stuck |
| Someone tries to finalize twice | The second call reverts with `PresaleAlreadyFinalized` |
| Buyer tries to claim before `enableClaims()` | Reverts with `ClaimsNotEnabled` |
| Buyer tries to claim before TGE | `vestedBps()` returns 0, so `claimableAmount` returns 0 — reverts with `NothingClaimable` |
| Marketing tries to queue before finalization | Reverts with `MarketingLocked` |
| Marketing tries to execute too early | Reverts with `TimelockNotReady` |
| Any operator requests more than is available | Reverts with `WithdrawalExceedsLimit` |

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
| `TimelockNotReady` | MarketingVault | `executeWithdrawal()` before 2-day wait |
| `NoQueuedWithdrawal` | MarketingVault | Execute or cancel with no pending queue |
| `WithdrawalExceedsLimit` | Dev/Team/MarketingVault | Requested amount exceeds available |
