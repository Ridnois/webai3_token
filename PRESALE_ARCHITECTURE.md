# WebAI3 Token Presale Architecture (Revised) v2.2

**Status:** Production-Grade Technical Baseline  
**Audience:** Smart Contract Engineers, Protocol Security Reviewers, External Auditors  
**Last Updated:** March 11, 2026

---

## Executive Summary

This revision preserves the approved architecture and closes the last production-grade gaps.

### Preserved Core Properties

- Vault-first routing for all presale funds
- Permissionless finalization
- Liquidity-before-claims ordering
- Dual-gated dev unlock model
- Bounded pause mechanism
- Mandatory presale vesting
- 7-phase fund-driven presale structure

### Final Hardening Added in v2.2

1. **Liquidity liveness hardening**
- Introduces `MAX_LIQUIDITY_DELAY = 7 days`.
- Adds permissionless fallback liquidity provisioning after deadline.
- Prevents indefinite claim lock if the liquidity executor fails.

2. **MarketingVault trust hardening**
- Applies explicit launch policy: **MarketingVault is fully locked until `presaleFinalized == true`**.
- Removes ambiguity about pre-finalization spending.

3. **Finalization timestamp hardening**
- Introduces immutable `PRESALE_END_TIMESTAMP`.
- Finalization condition is now:
  - `totalRaisedUSDC >= HARD_CAP` OR `block.timestamp >= PRESALE_END_TIMESTAMP`.
- Improves auditability and removes ambiguity from array-indexed phase end references.

### Launch Stability Summary

- Routing remains `70/15/10/5` (Liquidity/Dev/Team/Marketing).
- Presale vesting remains `30%` at TGE, `35%` at +3 months, `35%` at +6 months.
- At hard cap ($7M), liquidity receives $4.9M USDC, improving market depth at launch.

---

## Architecture Diagram

```text
Users
  |
  v
PresaleContract (phase pricing, accounting, finalization eligibility)
  |
  v
PresaleVault (hard split on each buy)
  |- LiquidityVault   [70%]  -> LP provisioning only
  |- DevRunwayVault   [15%]  -> min(milestone, stream, deposited)
  |- TeamStreamVault  [10%]  -> linear streaming only
  `- MarketingVault   [5%]   -> locked pre-finalization, then timelock+multisig

AIC Claim Module
  |
  `-> claimsEnabled only after liquidityProvisioned == true
```

### Liquidity Execution Paths

```text
Path A (Primary):
  LIQUIDITY_EXECUTOR_ROLE -> provideLiquidity()
  Allowed only until finalizedAt + MAX_LIQUIDITY_DELAY

Path B (Fallback):
  Anyone -> provideLiquidityFallback()
  Allowed only after finalizedAt + MAX_LIQUIDITY_DELAY
```

Both paths call the same internal liquidity provisioning logic and can execute only once.

---

## Fund Routing

### Mandatory Split Per Successful Buy

| Vault | Allocation | Purpose |
|---|---:|---|
| LiquidityVault | 70% | Launch liquidity depth and price stability |
| DevRunwayVault | 15% | Controlled R&D runway |
| TeamStreamVault | 10% | Team operational stream |
| MarketingVault | 5% | Post-finalization GTM budget |

### Liquidity Depth Context

At hard cap (`$7,000,000`):

- LiquidityVault receives `70% = $4,900,000` USDC.
- At listing target `$0.12`, paired token side target is `~40,833,333 AIC`.
- Buyer claims at TGE are capped to `30%` of presale allocation due to mandatory vesting.

This combination reduces immediate sell pressure and improves launch resilience.

### Mandatory Presale Vesting

| Unlock Time | Amount |
|---|---:|
| TGE | 30% |
| TGE + 3 months | 35% |
| TGE + 6 months | 35% |

---

## Vault Policies

### 1) LiquidityVault Policy (Liveness-Safe)

- Liquidity funds are dedicated to launch provisioning.
- No arbitrary treasury withdrawals.
- Provisioning can occur exactly once (`liquidityProvisioned` one-way flag).

#### Primary path

`provideLiquidity()` requirements:

- caller has `LIQUIDITY_EXECUTOR_ROLE`
- `presaleFinalized == true`
- `liquidityProvisioned == false`
- `block.timestamp <= finalizedAt + MAX_LIQUIDITY_DELAY`

#### Permissionless fallback path

`provideLiquidityFallback()` requirements:

- `presaleFinalized == true`
- `liquidityProvisioned == false`
- `block.timestamp > finalizedAt + MAX_LIQUIDITY_DELAY`

This guarantees liveness if the executor is unavailable.

#### Shared execution safeguards (both paths)

- immutable DEX router/factory targets
- immutable liquidity plan hash (`LIQUIDITY_PLAN_HASH`)
- minimum LP output / slippage guard
- emits `LiquidityProvisioned(...)`
- sets `liquidityProvisioned = true` on success

### 2) DevRunwayVault Policy (Dual-Gated Unlock)

Dev withdrawals require both milestone and stream maturity:

```text
withdrawableDev = max(
  0,
  min(milestoneUnlocked(totalRaisedUSDC), streamedDevAmount(now), devDeposited)
  - devWithdrawn
)
```

#### Stream Model

```text
DEV_MAX_BUDGET = HARD_CAP * 15% = 1,050,000 USDC
DEV_STREAM_DURATION = 180 days
streamedDevAmount(now) = DEV_MAX_BUDGET * min((now - presaleStartTimestamp)/180 days, 1)
```

#### Milestone Cap Table

| Cumulative Raised | Max Milestone-Unlocked Dev |
|---|---:|
| $500k | $50k |
| $1M | $120k |
| $2M | $250k |
| $3.5M | $420k |
| $5M | $650k |
| $6M | $850k |
| $7M | $1,050k |

### 3) TeamStreamVault Policy

- Funds stream linearly.
- No lump-sum drain function.
- Multisig receiver can only claim streamed amount.

### 4) MarketingVault Policy (Explicit Trust Rule)

**Selected policy: Option A (full pre-finalization lock).**

Rules:

- `marketingWithdrawable = 0` while `presaleFinalized == false`.
- After finalization, withdrawals require multisig approval and timelock delay.
- No owner/admin bypass.

Why this improves trust:

- Investors can verify that marketing funds cannot be spent before sale completion.
- Removes ambiguity around discretionary pre-launch spending.
- Maintains transparent, auditable post-finalization governance controls.

---

## Presale Phases

### 7-Phase Fund-Driven Schedule

| Phase | Cumulative Raise Range | Price (USDC/AIC) | Phase Token Cap (AIC) | Duration |
|---:|---|---:|---:|---:|
| 1 | $0 - $500k | $0.010 | 50,000,000 | 14 days |
| 2 | $500k - $1M | $0.013 | 38,500,000 | 14 days |
| 3 | $1M - $2M | $0.020 | 50,000,000 | 14 days |
| 4 | $2M - $3.5M | $0.028 | 53,600,000 | 21 days |
| 5 | $3.5M - $5M | $0.038 | 39,500,000 | 21 days |
| 6 | $5M - $6M | $0.053 | 18,900,000 | 21 days |
| 7 | $6M - $7M | $0.070 | 249,500,000 | 35 days |
| **Total** |  |  | **500,000,000** |  |

### Optional Anti-Whale (Retained)

- Phase 1 cap per wallet: `25,000 USDC`
- Phase 2 cap per wallet: `50,000 USDC`
- Phase 3+: open market

---

## Finalization Rules

### Immutable End Timestamp

```solidity
uint64 public immutable PRESALE_END_TIMESTAMP;
```

- Set once at initialization/deployment from the published phase schedule.
- Cannot be modified afterward.

### Permissionless Finalization Condition

```text
finalizable =
    (totalRaisedUSDC >= HARD_CAP)
    OR
    (block.timestamp >= PRESALE_END_TIMESTAMP)
```

### Finalization Pseudocode

```solidity
function finalizePresale() external {
    require(!presaleFinalized, "AlreadyFinalized");
    require(
        totalRaisedUSDC >= HARD_CAP || block.timestamp >= PRESALE_END_TIMESTAMP,
        "NotFinalizable"
    );

    presaleFinalized = true;
    presaleActive = false;
    finalizedAt = uint64(block.timestamp);

    emit PresaleFinalized(totalRaisedUSDC, totalTokensSold, finalizedAt);
}
```

No owner-only finalize function is permitted.

### Claims Ordering (Retained)

`enableClaims()` must require:

```text
presaleFinalized == true
AND
liquidityProvisioned == true
```

Strict order:

1. `finalizePresale()`
2. `provideLiquidity()` or `provideLiquidityFallback()`
3. `enableClaims()`

### State Machine (Updated)

```text
NotInitialized
  -> Active
Active
  -> Paused                         (bounded)
Paused
  -> Active                         (manual or forceUnpause)
Active/Paused
  -> EndEligible                    (hard cap OR PRESALE_END_TIMESTAMP)
EndEligible
  -> Finalized                      (permissionless)
Finalized
  -> LiquidityPending               (executor window)
LiquidityPending
  -> LiquidityProvisioned           (executor path)
LiquidityPending
  -> LiquidityFallbackOpen          (now > finalizedAt + MAX_LIQUIDITY_DELAY)
LiquidityFallbackOpen
  -> LiquidityProvisioned           (permissionless fallback path)
LiquidityProvisioned
  -> ClaimsEnabled
```

---

## Security Controls

### Role Set (Minimal and Clear)

- `PAUSER_ROLE`: pause/unpause buys, within bounded limits.
- `LIQUIDITY_EXECUTOR_ROLE`: primary liquidity path before fallback deadline.
- `VAULT_MULTISIG_ROLE`: dev/team/marketing vault withdrawals per policy.
- `DEFAULT_ADMIN_ROLE`: role management only; no finalize/claim/liquidity bypass.

### Objective, Onchain-Enforceable Restrictions

- Finalization is permissionless and condition-based.
- Liquidity fallback opens automatically by timestamp condition.
- Claims require actual `liquidityProvisioned == true`.
- Marketing withdrawals blocked until `presaleFinalized == true`.

### Critical Non-Bypass Rules

- No privileged route to set `liquidityProvisioned` without real LP execution checks.
- No route to enable claims before liquidity provisioning.
- No route to spend MarketingVault pre-finalization.
- No owner/admin early-close path.

### Pause Safety (Retained)

- `MAX_SINGLE_PAUSE = 72h`
- `MAX_CUMULATIVE_PAUSE = 14d`
- pause blocks new buys only
- pause never blocks finalization or liquidity fallback calls

---

## Testing Strategy

### 1) Finalization Timestamp Hardening Tests

- finalization reverts before hard cap and before `PRESALE_END_TIMESTAMP`
- finalization succeeds exactly at `PRESALE_END_TIMESTAMP`
- finalization succeeds at hard cap regardless of timestamp

### 2) Liquidity Liveness Tests

- primary `provideLiquidity()` succeeds before fallback deadline with role
- primary path reverts without role
- fallback path reverts before deadline
- fallback path succeeds permissionlessly after deadline
- `liquidityProvisioned` cannot be set twice

### 3) Claims Ordering Tests

- `enableClaims()` reverts if not finalized
- `enableClaims()` reverts if finalized but liquidity not provisioned
- claims succeed only after both conditions are true

### 4) MarketingVault Trust Tests

- marketing withdrawal reverts pre-finalization
- marketing withdrawal succeeds post-finalization only with timelock + multisig
- admin/owner cannot bypass pre-finalization lock

### 5) Dev Dual-Gate Tests

- milestone reached but stream lagging: stream cap binds
- stream matured but milestone unmet: milestone cap binds
- fast raise cannot drain full dev allocation immediately

### 6) Pause Abuse and Liveness Tests

- pause blocks buys only
- finalization callable while paused
- fallback liquidity callable while paused after deadline
- pause budget limits enforced

### 7) Invariant / Fuzz Tests

- `claimsEnabled => presaleFinalized && liquidityProvisioned`
- `liquidityProvisioned` flips at most once
- bucket accounting conservation holds under random buy/withdraw sequences
- marketing spent is zero whenever `presaleFinalized == false`

---

## Operational Playbook

### Pre-Launch Setup

1. Deploy with immutable constants:
- `HARD_CAP`
- `PRESALE_END_TIMESTAMP`
- `MAX_LIQUIDITY_DELAY`
- DEX route config / liquidity plan hash
2. Configure roles and multisig signers.
3. Publish public policy and parameter commitments.

### During Presale

1. Monitor raised amount, active phase, vault balances.
2. Monitor dev stream and milestone utilization.
3. Ensure MarketingVault remains untouched pre-finalization.
4. Use pause only for security incidents within bounds.

### Finalization and Launch

1. Anyone calls `finalizePresale()` once eligible.
2. Primary liquidity executor attempts provisioning.
3. If deadline passes without provisioning, any actor executes fallback liquidity path.
4. Enable claims only after `liquidityProvisioned == true`.
5. Begin claim schedule per vesting policy.

### Incident Handling

- If executor is unavailable, trigger fallback after deadline.
- Never bypass ordering invariants to restore UX.
- Publish incident and remediation timeline.

---

## Reference Constants / Critical Invariants

### Reference Constants

- `HARD_CAP = 7_000_000e6` USDC
- `PRESALE_TOKEN_CAP = 500_000_000e18` AIC
- `ROUTING_SPLIT = 70/15/10/5`
- `PRESALE_VESTING = 30% / 35% / 35%`
- `DEV_STREAM_DURATION = 180 days`
- `MAX_SINGLE_PAUSE = 72 hours`
- `MAX_CUMULATIVE_PAUSE = 14 days`
- `MAX_LIQUIDITY_DELAY = 7 days`
- `PRESALE_END_TIMESTAMP` (immutable)

### Critical Invariants

1. All accepted presale funds route through `PresaleVault`.
2. Finalization is permissionless and objective-condition based.
3. `claimsEnabled => presaleFinalized && liquidityProvisioned`.
4. If `!liquidityProvisioned` and `now > finalizedAt + MAX_LIQUIDITY_DELAY`, fallback liquidity path is callable by anyone.
5. MarketingVault withdrawals are impossible while `presaleFinalized == false`.
6. Dev withdrawals satisfy: `devWithdrawn <= min(milestoneUnlocked, streamedDevAmount, devDeposited)`.
7. `sum(phaseTokenCaps) == 500,000,000 AIC`.
8. No privileged role can bypass invariants 2–6.

---

This document is the production-ready baseline for implementation and third-party audit preparation.
