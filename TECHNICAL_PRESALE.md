# Technical Specification: Presale Contract (Proposed)

## Overview

The `PresaleContract` is a separate smart contract (not part of `webai3-token`) that manages a multi-phase token presale. Users purchase AIC tokens by sending USDC to this contract during active presale phases. Each phase has a different price and allocation cap.

**Contract Name:** `PresaleContract` (TBD - location in webai3_web or webai3-landing)
**Status:** Specification (not yet implemented)

---

## Design Principles

1. **Single Responsibility** — Presale logic only, token is separate
2. **Phase-Based** — Multiple phases with increasing prices over time
3. **Time-Driven** — Phases determined by `block.timestamp`
4. **Allocation-Capped** — Each phase has max tokens
5. **No Vesting** — Tokens distributed immediately (vesting is optional, phase 2)
6. **Simple Refunds** — Refund if presale fails to reach soft cap (optional)
7. **Admin Control** — Owner can adjust phases, withdraw funds

---

## Core Concepts

### Phase Structure

Each presale phase is defined by:

```solidity
struct Phase {
    uint256 startTime;      // Unix timestamp when phase begins
    uint256 endTime;        // Unix timestamp when phase ends
    uint256 pricePerToken;  // USDC per AIC (in USDC base units, 6 decimals)
                            // e.g., 0.5e6 = $0.50, 1e6 = $1.00
    uint256 maxTokens;      // Max AIC tokens available in this phase
    uint256 soldTokens;     // Cumulative AIC sold (state, incremented)
}
```

**Example Phase Configuration:**

```solidity
Phase({
    startTime: 1741336800,      // March 11, 2026 10:00 UTC
    endTime: 1742000800,        // March 18, 2026 10:00 UTC (7 days)
    pricePerToken: 0.5e6,       // 0.50 USDC per token
    maxTokens: 100_000_000 ether,  // 100M tokens available
    soldTokens: 0               // Updated as sales occur
})
```

### Phase Progression

Phases are strictly ordered in time. No gaps allowed.

```
Phase 0: Mar 11-18  (0.50 USDC per token)
Phase 1: Mar 18-25  (0.75 USDC per token)
Phase 2: Mar 25-Apr 1 (1.00 USDC per token)
Phase 3: Apr 1-May 1 (public sale, higher price)
```

---

## State Variables

```solidity
// Immutable
IERC20 public immutable usdc;   // USDC token (0x833589fCD6... on Base)
IERC20 public immutable aic;    // AIC token (WebAI3Token address)
address public immutable owner; // Admin who can withdraw, adjust phases

// Mutable
Phase[] public phases;          // Array of presale phases

// Accounting
mapping(address => uint256) public contributed;  // Total USDC spent per user
mapping(address => uint256) public tokensClaimed;  // Total AIC received per user

// Optional: Soft cap for refunds
uint256 public softCapUSDC;     // Min USDC to raise (or enable refunds)
bool public presaleFailed;      // If true, users can refund
```

---

## Constructor

```solidity
constructor(
    address _usdc,
    address _aic,
    uint256 _softCapUSDC
)
```

**Parameters:**
- `_usdc` — USDC token address on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
- `_aic` — AIC token address (deployed WebAI3Token)
- `_softCapUSDC` — Minimum USDC to raise (optional, can be 0)

**Validation:**
- Both token addresses must not be zero
- Both tokens must support ERC-20 interface

---

## Phase Management (Admin-Only)

### Set Phases

```solidity
function setPhases(Phase[] memory _phases) external onlyOwner
```

Replace all presale phases with new configuration.

**Validation:**
- Must have at least 1 phase
- Phases must be ordered by `startTime`
- No gaps: each phase's `endTime` must equal next phase's `startTime`
- All `maxTokens` must be > 0
- All `pricePerToken` must be > 0
- `startTime` must be in the future

**Invariant:** Can only be called before presale starts (when no phases are active).

**Example:**
```solidity
Phase[] memory phases = new Phase[](3);
phases[0] = Phase(1741336800, 1742000800, 0.5e6, 100_000_000 ether, 0);
phases[1] = Phase(1742000800, 1742605200, 0.75e6, 100_000_000 ether, 0);
phases[2] = Phase(1742605200, 1743210000, 1.0e6, 100_000_000 ether, 0);
presale.setPhases(phases);
```

### Mark Presale Failed (Optional)

```solidity
function markFailed() external onlyOwner
```

Called if presale didn't reach soft cap. Enables `refund()` for users.

**Condition:** Only callable after presale end time and if `totalRaisedUSDC < softCapUSDC`.

---

## Presale Participation

### Get Active Phase

```solidity
function getActivePhase() external view returns (uint256 phaseIndex)
```

Returns the index of the currently active phase based on `block.timestamp`.

**Logic:**
```solidity
for (uint256 i = 0; i < phases.length; i++) {
    if (block.timestamp >= phases[i].startTime &&
        block.timestamp < phases[i].endTime) {
        return i;
    }
}
revert NoActivePhase();
```

**Returns:** Phase index (0, 1, 2, etc.)

**Reverts:** `NoActivePhase()` if no phase is currently active.

### Buy Tokens

```solidity
function buy(uint256 usdcAmount) external returns (uint256 aicAmount)
```

**Parameters:**
- `usdcAmount` — Amount of USDC to spend (in USDC base units, 6 decimals)

**Execution:**
1. Determine active phase
2. Calculate AIC tokens owed: `aicAmount = (usdcAmount * 1e18) / phase.pricePerToken`
3. Validate phase cap not exceeded: `phase.soldTokens + aicAmount <= phase.maxTokens`
4. Transfer USDC from buyer to contract: `usdc.safeTransferFrom(msg.sender, address(this), usdcAmount)`
5. Transfer AIC from contract to buyer: `aic.safeTransfer(msg.sender, aicAmount)`
6. Update phase: `phase.soldTokens += aicAmount`
7. Update accounting: `contributed[msg.sender] += usdcAmount`, `tokensClaimed[msg.sender] += aicAmount`
8. Emit `BuyTokens(msg.sender, usdcAmount, aicAmount, phaseIndex)`

**Returns:** `aicAmount` purchased.

**Reverts:**
- `NoActivePhase()` — No phase currently active
- `PhaseCapExceeded()` — Not enough tokens remaining in phase
- `InsufficientAllowance()` — Buyer hasn't approved enough USDC

**Example:**
```solidity
// User has 1000 USDC in wallet
usdc.approve(address(presale), 1000e6);
uint256 aicAmount = presale.buy(1000e6);
// If Phase 0 (0.5 USDC per token):
//   aicAmount = 1000e6 * 1e18 / 0.5e6 = 2000e18 = 2000 AIC
```

### Buy Multiple Times

Users can call `buy()` multiple times:

```solidity
// Phase 0: Buy 1000 AIC at 0.50 USDC/token = 500 USDC
presale.buy(500e6);

// Phase 1: Buy 1000 AIC at 0.75 USDC/token = 750 USDC
presale.buy(750e6);

// Total: 2000 AIC, 1250 USDC contributed
assert(tokensClaimed[user] == 2000e18);
assert(contributed[user] == 1250e6);
```

---

## Refunds (Optional)

### Request Refund

```solidity
function refund() external
```

If presale failed to reach soft cap, users can refund their USDC and lose their AIC.

**Conditions:**
- `presaleFailed == true` (admin called `markFailed()`)
- `contributed[msg.sender] > 0` (user participated)

**Execution:**
1. Get refund amount: `uint256 refundAmount = contributed[msg.sender]`
2. Clear state: `contributed[msg.sender] = 0`, `tokensClaimed[msg.sender] = 0`
3. Return AIC: `aic.safeTransferFrom(msg.sender, address(this), aicAmount)`
4. Send USDC: `usdc.safeTransfer(msg.sender, refundAmount)`
5. Emit `Refund(msg.sender, refundAmount, aicAmount)`

**Reverts:**
- `PresaleSucceeded()` — Presale didn't fail (can't refund)
- `NothingToRefund()` — User has no contribution

**Note:** Requires users to hold AIC to receive refund. Only works if tokens were distributed immediately (no vesting).

---

## Views

### Get Phase Details

```solidity
function getPhase(uint256 index) external view returns (Phase memory)
```

Returns phase configuration by index.

### Get Total Phases

```solidity
function getPhaseCount() external view returns (uint256)
```

Returns number of presale phases.

### Get User Info

```solidity
function getUserInfo(address user) external view returns (
    uint256 contributed,
    uint256 tokensClaimed,
    uint256 aicBalance
)
```

Returns how much user spent, how many AIC they own, and current AIC balance.

### Check Presale Status

```solidity
function getPresaleStatus() external view returns (
    uint256 activePhaseIndex,
    uint256 totalRaisedUSDC,
    uint256 totalTokensSold
)
```

Returns:
- `activePhaseIndex` — Current active phase (or type(uint256).max if none)
- `totalRaisedUSDC` — Total USDC raised across all phases
- `totalTokensSold` — Total AIC sold across all phases

---

## Admin Functions

### Withdraw USDC

```solidity
function withdrawUSDC() external onlyOwner returns (uint256 amount)
```

Called after presale ends successfully. Withdraws all USDC to owner.

**Conditions:**
- All presale phases must be ended: `block.timestamp >= phases[lastPhase].endTime`
- Presale must not have failed: `!presaleFailed`

**Execution:**
1. Get balance: `uint256 amount = usdc.balanceOf(address(this))`
2. Transfer to owner: `usdc.safeTransfer(owner, amount)`
3. Emit `WithdrawUSDC(amount)`

**Returns:** Amount withdrawn.

### Emergency Withdraw AIC

```solidity
function emergencyWithdrawAIC() external onlyOwner returns (uint256 amount)
```

Withdraw remaining AIC if presale ends with unsold tokens.

**Conditions:**
- All presale phases must be ended
- Only for leftover tokens (after all buyers claim)

**Execution:**
1. Get balance: `uint256 amount = aic.balanceOf(address(this))`
2. Transfer to owner: `aic.safeTransfer(owner, amount)`
3. Emit `EmergencyWithdrawAIC(amount)`

---

## Time Progression

### How Phases Advance

No automatic transitions. Phases advance when users call functions and contract checks `block.timestamp`.

```
Deployment: Block 1000, block.timestamp = 1741336800
  ↓
Phase 0 active: User A calls buy() at 1741336800
  → Contract checks: Is 1741336800 >= startTime AND < endTime? YES
  → Price = 0.5 USDC per token ✓
  ↓
[7 days pass, blocks accumulate]
  ↓
Phase 1 active: User B calls buy() at 1741940000
  → Contract checks: Is 1741940000 >= Phase 1 startTime? YES
  → Price = 0.75 USDC per token ✓
  ↓
[Presale ends]
  ↓
Post-presale: Admin calls withdrawUSDC() at 1743300000
  → Checks: All phases ended? YES
  → Transfers USDC ✓
```

### No Scheduled Actions

The contract does NOT:
- Automatically pause when phases end
- Automatically transfer funds anywhere
- Automatically generate reports

All actions are triggered by external calls (users buying, admin withdrawing).

---

## State Machine

```
Setup Phase:
  ├─ Owner calls setPhases()
  └─ Owner adjusts phases as needed

Presale Running:
  ├─ User calls buy() during active phase
  ├─ Tokens transferred immediately
  ├─ USDC held in contract
  └─ [repeat for multiple users/phases]

Presale Ended:
  ├─ Owner checks if soft cap reached
  ├─ If failed: Owner calls markFailed()
  │  └─ Users call refund() to reclaim USDC
  ├─ If succeeded: Owner calls withdrawUSDC()
  │  └─ USDC sent to owner
  └─ Owner calls emergencyWithdrawAIC() for leftovers

Post-Presale:
  └─ Token contract integrates with staking, farming, etc.
```

---

## Integration with WebAI3Token

### Requirements

1. **Token Address Known** — PresaleContract must be deployed AFTER AIC token
2. **Sufficient Allocation** — AIC token must have reserved tokens for presale
   - Example: 200M AIC allocated to presale contract at token deployment
3. **USDC on Base** — Contract assumes USDC is at `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

### Token Flow

```
Deployment:
  WebAI3Token mints 1B AIC total:
  ├─ 350M to community
  ├─ 200M to team
  ├─ 150M to investors
  ├─ 150M to treasury
  ├─ 100M to incentives
  └─ 50M to liquidity

PresaleContract deployed:
  └─ Receives 200M AIC via transfer from treasury/admin
     (or allocated at token deployment)

Presale runs:
  ├─ User sends USDC to PresaleContract
  ├─ PresaleContract sends AIC to user
  └─ USDC accumulates in contract

Post-presale:
  ├─ Admin withdraws USDC (profit)
  └─ Leftover AIC returned to treasury
```

---

## Security Considerations

### ReEntrancy

**Threat:** User calls `buy()`, contract calls `aic.transfer()`, AIC token callback reenters and calls `buy()` again.

**Mitigation:**
- Use OpenZeppelin `SafeERC20` (guards against reentrancy)
- Checks-Effects-Interactions pattern: validate, then transfer

### Price Precision

**Threat:** Rounding errors in token calculation.

**Calculation:** `aicAmount = (usdcAmount * 1e18) / phase.pricePerToken`

Example with Phase 0 (0.5 USDC per token):
```
100 USDC = (100e6 * 1e18) / 0.5e6 = 200e18 = 200 AIC ✓

1 USDC = (1e6 * 1e18) / 0.5e6 = 2e18 = 2 AIC ✓

1 USDC (0.1 USDC minimum):
  (0.1e6 * 1e18) / 0.5e6 = 0.2e18 = 0.2 AIC ✓ (10^16 precision)

Very small amount (1 wei USDC):
  (1 * 1e18) / 0.5e6 = 2000 wei AIC ✓ (dust)
```

Rounding down is acceptable (users lose dust, not significant).

### Flash Loan Attack

**Threat:** Attacker uses flash loan to get max phase cap in one transaction.

**Reality:** No governance voting attached to presale, so flash loan doesn't help.

**Mitigation:** None needed (not a concern for simple presale).

### Soft Cap Manipulation

**Threat:** Owner marks presale as failed when it succeeded.

**Mitigation:**
- Transparent accounting (totalRaisedUSDC visible on-chain)
- Community can audit if claim is false
- Consider: Governance vote to approve refund, not just admin

### No Vesting Risk

**Current Design:** Tokens distributed immediately.

**Threat:** Buyer receives tokens, sells immediately, dumps price.

**Mitigation (Phase 2):** Implement vesting (linear release over time, e.g., 6 months).

---

## Events

```solidity
event BuyTokens(
    address indexed buyer,
    uint256 usdcAmount,
    uint256 aicAmount,
    uint256 indexed phaseIndex
);

event Refund(
    address indexed user,
    uint256 usdcRefunded,
    uint256 aicReturned
);

event PhasesUpdated(uint256 phaseCount);

event PresaleMarkedFailed();

event WithdrawUSDC(uint256 amount);

event EmergencyWithdrawAIC(uint256 amount);
```

---

## Custom Errors

```solidity
error NoActivePhase();
error PhaseCapExceeded();
error InsufficientAllowance();
error PresaleSucceeded();
error NothingToRefund();
error InvalidPhaseConfig();
error PhasesNotOrdered();
error InvalidTokenAddress();
```

---

## Testing Strategy

### Unit Tests

- ✅ Constructor validation
- ✅ Phase setting (validation, ordering)
- ✅ Phase lookup (getActivePhase)
- ✅ Buy during each phase (correct pricing)
- ✅ Buy multiple times
- ✅ Phase cap enforcement
- ✅ USDC transfer validation
- ✅ Admin withdraw
- ✅ Refund logic (if failed)
- ✅ Events emitted correctly

### Fuzz Tests

- ✅ Buy with random USDC amounts
- ✅ Multiple buyers at different times
- ✅ Price calculation precision

### Invariants

- ✅ `totalTokensSold == sum(allContributions)` (accounting)
- ✅ `totalRaisedUSDC == sum(allBuys)` (USDC accounting)
- ✅ `aic.balanceOf(contract) >= totalTokensSold` (contract has tokens)
- ✅ `phase.soldTokens <= phase.maxTokens` (per-phase cap)

---

## Deployment Checklist

- [ ] AIC token deployed with allocation for presale
- [ ] USDC address verified on Base
- [ ] Phase configuration finalized (dates, prices, caps)
- [ ] Soft cap amount set (if using refunds)
- [ ] Admin address set (should be multisig)
- [ ] PresaleContract deployed
- [ ] Verify contract address in documentation
- [ ] Transfer presale allocation from treasury to contract
- [ ] Test buy() on testnet
- [ ] Test withdrawal on testnet
- [ ] Approve contract in governance
- [ ] Launch presale

---

## Future Enhancements

### Phase 2: Vesting

Add linear vesting to prevent immediate dumps:

```solidity
struct Vesting {
    uint256 cliff;          // Days before any tokens unlock
    uint256 duration;       // Days to fully unlock
}

mapping(address => uint256) public claimableAtBlock;
```

### Phase 2: Whitelist

Add allowlist for early phases:

```solidity
mapping(address => bool) public whitelisted;
mapping(address => uint256) public whitelistCap;  // Max per user
```

### Phase 2: Referral Program

Reward users who refer others:

```solidity
mapping(address => uint256) public referralRewards;
```

### Phase 2: KYC Integration

Integrate with KYC provider (requires off-chain oracle).

### Phase 3: Multiple Payment Tokens

Accept ETH, USDC, USDT, etc.

```solidity
mapping(address => uint256) public tokenPrices;  // Price in USDC equivalent
```

---

## References

- Base Testnet: https://sepolia.basescan.org
- USDC on Base: https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
- OpenZeppelin SafeERC20: https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
