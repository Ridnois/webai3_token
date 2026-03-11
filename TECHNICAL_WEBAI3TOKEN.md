# Technical Specification: WebAI3Token Contract

## Overview

`WebAI3Token` is an immutable ERC-20 governance token for the WebAI3 platform deployed on Base L2. The entire token supply (1B AIC) is minted at deployment through genesis allocations. No post-deployment minting is possible.

**Contract Address:** (TBD - set after mainnet deployment)
**Network:** Base L2 (Chain ID 8453)
**Testnet:** Base Sepolia (Chain ID 84532)

---

## Contract Design

### Core Principles

1. **Immutable Supply** — 1B tokens minted once, never more
2. **Audited Primitives** — All functionality inherited from OpenZeppelin v5 (no custom logic)
3. **Fixed Allocations** — Distribution determined at deployment, cannot change
4. **Operational Safety** — Pause mechanism for emergency response
5. **Governance Compatible** — Supports delegation and voting

### Inheritance Chain

```
WebAI3Token
├── ERC20
│   └── Handles standard token operations (transfer, approve, balanceOf)
├── ERC20Pausable
│   └── Adds pause/unpause (freezes all transfers)
├── ERC20Permit
│   └── Adds permit() for gasless approvals (EIP-2612)
├── ERC20Votes
│   └── Adds delegation and voting power tracking
└── AccessControl
    └── Adds role-based permissions (admin, pauser)
```

### State Variables

```solidity
// Constants
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;  // 1e27 base units
```

Inherited from OpenZeppelin:
- `_balances: mapping(address => uint256)` — Token balances per address
- `_allowances: mapping(address => mapping(address => uint256))` — Approved spending per address
- `_totalSupply: uint256` — Total tokens in circulation (set once, never changes)
- `_paused: bool` — Pause state (false = operating, true = paused)
- `_roles: mapping(bytes32 => mapping(address => bool))` — Role assignments
- `_delegates: mapping(address => address)` — Voting delegation per address
- `_checkpoints: mapping(address => Checkpoint[])` — Historical voting power (for governance)
- `_nonces: mapping(address => uint256)` — Permit nonce per address (prevents replay)

---

## Constructor

### Signature

```solidity
constructor(address admin, Allocation[] memory allocations)
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `admin` | `address` | Address to receive `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Must not be zero. |
| `allocations` | `Allocation[]` | Array of recipients and amounts. Sum must equal `MAX_SUPPLY`. |

### Allocation Struct

```solidity
struct Allocation {
    address recipient;  // Recipient address (must not be zero)
    uint256 amount;     // Tokens to mint in base units (1e18 = 1 token)
}
```

### Execution Steps

1. **Validate Admin**
   ```solidity
   if (admin == address(0)) revert InvalidAdmin(admin);
   ```

2. **Validate Allocations**
   ```solidity
   if (allocations.length == 0) revert EmptyAllocations();
   ```

3. **Grant Roles**
   ```solidity
   _grantRole(DEFAULT_ADMIN_ROLE, admin);
   _grantRole(PAUSER_ROLE, admin);
   ```

4. **Mint Tokens**
   ```solidity
   for (uint256 i = 0; i < allocations.length; ++i) {
       Allocation memory allocation = allocations[i];
       if (allocation.recipient == address(0))
           revert InvalidAllocationRecipient(i);
       totalAllocated += allocation.amount;
       _mint(allocation.recipient, allocation.amount);
   }
   ```

5. **Verify Total Supply**
   ```solidity
   if (totalAllocated != MAX_SUPPLY)
       revert InvalidAllocationTotal(MAX_SUPPLY, totalAllocated);
   ```

### Custom Errors

| Error | Parameters | Meaning |
|---|---|---|
| `InvalidAdmin` | `address admin` | Constructor received zero address as admin |
| `EmptyAllocations` | — | Constructor received empty allocations array |
| `InvalidAllocationRecipient` | `uint256 index` | Allocation at `index` has zero address recipient |
| `InvalidAllocationTotal` | `uint256 expected, uint256 actual` | Sum of allocations ≠ MAX_SUPPLY |

### Example Deployment

```solidity
WebAI3Token.Allocation[] memory allocations = new WebAI3Token.Allocation[](6);

allocations[0] = WebAI3Token.Allocation({
    recipient: 0x1111...,  // Community wallet
    amount: 350_000_000 ether  // 35% = 350M tokens
});

allocations[1] = WebAI3Token.Allocation({
    recipient: 0x2222...,  // Team wallet
    amount: 200_000_000 ether  // 20% = 200M tokens
});

// ... more allocations summing to exactly 1_000_000_000 ether

WebAI3Token token = new WebAI3Token(
    0x9999...,  // admin address
    allocations
);
```

---

## Public Functions

### Standard ERC-20

Inherited from `ERC20`. No overrides.

```solidity
// Transfers
function transfer(address to, uint256 value) external returns (bool)
function transferFrom(address from, address to, uint256 value) external returns (bool)

// Approvals
function approve(address spender, uint256 value) external returns (bool)
function increaseAllowance(address spender, uint256 addedValue) external returns (bool)
function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool)

// Views
function balanceOf(address account) external view returns (uint256)
function allowance(address owner, address spender) external view returns (uint256)
function totalSupply() external view returns (uint256)  // Always 1_000_000_000 ether
function decimals() external pure returns (uint8)  // Always 18
function name() external pure returns (string)  // "WebAI3 Token"
function symbol() external pure returns (string)  // "AIC"
```

### Pausable

Inherited from `ERC20Pausable`.

```solidity
function pause() external onlyRole(PAUSER_ROLE)
```
Freezes all transfers (and `transferFrom`). Approvals still work. Emit `Paused(address indexed account)`.

```solidity
function unpause() external onlyRole(PAUSER_ROLE)
```
Re-enables transfers. Emit `Unpaused(address indexed account)`.

```solidity
function paused() external view returns (bool)
```
Returns current pause state.

### Voting & Delegation

Inherited from `ERC20Votes`.

```solidity
function delegate(address delegatee) external
```
Delegate voting power to `delegatee` (can be self). Emit `DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)`.

```solidity
function getVotes(address account) external view returns (uint256)
```
Current voting power of `account`. Includes delegated power received from others.

```solidity
function getPastVotes(address account, uint256 blockNumber) external view returns (uint256)
```
Historical voting power at a specific block. Used by governance contracts to vote based on historic holdings.

```solidity
function getPastTotalSupply(uint256 blockNumber) external view returns (uint256)
```
Total supply at a specific block (always `MAX_SUPPLY` because no minting post-deployment).

### Permit (Gasless Approvals)

Inherited from `ERC20Permit`.

```solidity
function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
) external
```
Approve spending via ECDSA signature (EIP-2612). Signer is derived from signature; does not require `owner` to call.

**Use case:**
```solidity
// Off-chain: User signs a message
bytes32 digest = token.DOMAIN_SEPARATOR();  // EIP-712 domain
bytes32 structHash = keccak256(abi.encode(
    PERMIT_TYPEHASH,
    owner,
    spender,
    value,
    nonce,
    deadline
));
// Sign digest with owner's private key → (v, r, s)

// On-chain: Anyone can submit the signed permit
token.permit(owner, spender, value, deadline, v, r, s);
// Now spender is approved for value tokens
```

```solidity
function nonces(address owner) external view returns (uint256)
```
Current permit nonce (increments on each permit). Prevents replay attacks.

```solidity
function DOMAIN_SEPARATOR() external view returns (bytes32)
```
EIP-712 domain separator (used for permit signature verification).

```solidity
function PERMIT_TYPEHASH() external pure returns (bytes32)
```
EIP-2612 permit type hash.

### Access Control

Inherited from `AccessControl`.

```solidity
function hasRole(bytes32 role, address account) external view returns (bool)
```
Check if `account` has `role`.

```solidity
function getRoleAdmin(bytes32 role) external view returns (bytes32)
```
Admin role for `role`. For all roles in this contract, it's `DEFAULT_ADMIN_ROLE`.

```solidity
function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role))
```
Grant `role` to `account`. Must be called by someone with admin role for that role.

```solidity
function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role))
```
Revoke `role` from `account`.

```solidity
function renounceRole(bytes32 role, address caller) external
```
Renounce a role you hold (only you can call this).

### Internal Functions

```solidity
function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable, ERC20Votes)
```
Internal hook called on every transfer. Overrides multiple parents:
- `ERC20._update()` — updates balances
- `ERC20Pausable._update()` — checks pause state
- `ERC20Votes._update()` — updates voting checkpoints

Calls `super._update()` to invoke all parent implementations (MRO resolution).

```solidity
function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256)
```
Returns permit nonce. Overrides both parents for consistency.

---

## State Transitions

### Pause Lifecycle

```
Deployed (paused = false)
    ↓
admin calls pause()
    ↓
Paused (paused = true)
  - Transfers blocked
  - Approvals work
  - Delegation works
    ↓
admin calls unpause()
    ↓
Resumed (paused = false)
```

### Voting Delegation

```
User receives tokens
  ↓
User's voting power = 0 (not delegated to self)
  ↓
User calls delegate(user) — delegates to self
  ↓
User's voting power = user's balance
  ↓
Governance contract checks user's voting power
  ↓
User can vote in proportion to balance
```

---

## Gas Optimization Notes

### Constructor
- ~200k gas (minting 1B tokens to 6 addresses)
- One-time cost

### Transfer
- ~51k gas (cold slot read/write)
- ~29k gas (warm slot)
- Pausable check adds minimal overhead (~200 gas)
- Votes checkpoint adds ~5k-20k gas (depends on checkpoint history)

### Delegate
- ~30k-50k gas (depends on existing delegations and checkpoints)

### Permit
- ~2.5k gas (signature verification + nonce check + approval)
- Saves ~25k gas vs separate approve() + transferFrom()

### No Gas Surprises
- No loops (except constructor allocation loop, which runs once)
- No external calls
- No reentrancy risk (ERC20 transfer hooks use OpenZeppelin's checks)
- Voting checkpoints are efficient (binary search for historical lookups)

---

## Security Analysis

### Immutability

**Threat:** Token supply could be changed via contract upgrade or backdoor mint.

**Mitigation:**
- No `mint()` or `burn()` functions exist
- No upgrade mechanism (not a proxy)
- Supply is hardcoded constant: `MAX_SUPPLY = 1_000_000_000 ether`
- Constructor validates allocations sum exactly to `MAX_SUPPLY`

### Pause Abuse

**Threat:** Admin could pause forever, locking tokens.

**Mitigation:**
- Pause is only for emergency response
- Governance can remove pauser via `revokeRole(PAUSER_ROLE, admin)`
- No time-lock required (assumes trust in governance)
- Consider: multisig for pauser role in production

### Permit Replay

**Threat:** Same signature could be used multiple times.

**Mitigation:**
- Nonce increments on each permit
- Deadline parameter prevents old signatures from being replayed
- EIP-712 domain separator ties signature to chain ID

### Access Control

**Threat:** Unauthorized role grants.

**Mitigation:**
- Only `DEFAULT_ADMIN_ROLE` can grant roles
- Initially held by trusted admin address
- Can transfer via `grantRole()` + `renounceRole()`

### Voting Power Attacks

**Threat:** Flash loans used to vote (attacker borrows tokens, votes, returns).

**Mitigation:**
- Voting power based on block history, not current balance
- `getPastVotes(account, blockNumber)` checks balance at specific past block
- Governance contract should vote based on block where proposal was created, not current block

### Reentrancy

**Threat:** Transfer callback reenters contract.

**Mitigation:**
- ERC20 has no transfer hooks (unlike ERC777)
- OpenZeppelin ERC20Votes uses `_update()` hook (safe internal call)
- No external calls in contract

---

## Integration Points

### Token Holders
- Call `transfer()` to send tokens
- Call `approve()` + authorize others to call `transferFrom()`
- Call `delegate()` to participate in governance voting
- Use `permit()` for gasless approvals

### Governance Contracts
- Call `getVotes(account)` for current voting power
- Call `getPastVotes(account, blockNumber)` for historical voting power
- Check `hasRole()` to verify admin status

### DEX / Trading
- Standard ERC-20, compatible with Uniswap, Curve, etc.
- Can be listed on any exchange supporting ERC-20

### Presale Contract
- Receives initial allocation (e.g., 200M tokens)
- Calls `transfer()` to distribute tokens to buyers
- Never calls `mint()` (doesn't exist)

### Staking / Reward Contracts
- Receive allocation of tokens for staking rewards
- Distribute via `transfer()`

---

## Events

All events inherited from OpenZeppelin:

```solidity
event Transfer(address indexed from, address indexed to, uint256 value)
event Approval(address indexed owner, address indexed spender, uint256 value)
event Paused(address indexed account)
event Unpaused(address indexed account)
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)
event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance)
event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)
```

---

## Deployment Checklist

- [ ] Verify admin address is secure (multisig recommended)
- [ ] Verify all 6 allocations sum to exactly 1,000,000,000 ether
- [ ] Verify recipient addresses are correct (no typos)
- [ ] Verify addresses are not contract addresses (use EOAs if possible, or multisigs)
- [ ] Run full test suite: `forge test --gas-report`
- [ ] Test pause/unpause on testnet
- [ ] Test delegation on testnet
- [ ] Test permit signature on testnet
- [ ] Record deployed address in DEPLOYMENT.md
- [ ] Update presale contract with token address
- [ ] Update governance contracts with token address
- [ ] Announce deployment in documentation

---

## Production Considerations

### Admin Wallet Security
- Use multisig (e.g., Gnosis Safe) as admin
- Require M-of-N approval for pause/unpause
- Store private keys securely (hardware wallet, cold storage)

### Role Transfer
If admin needs to change (e.g., from deployer to governance):
1. Multisig calls `grantRole(DEFAULT_ADMIN_ROLE, newAdmin)`
2. Multisig calls `grantRole(PAUSER_ROLE, newAdmin)`
3. Multisig calls `renounceRole(DEFAULT_ADMIN_ROLE, oldAdmin)`
4. Multisig calls `renounceRole(PAUSER_ROLE, oldAdmin)`

### Monitoring
- Watch for Transfer events (suspicious large transfers)
- Watch for Paused/Unpaused events (unexpected pauses)
- Watch for RoleGranted/RoleRevoked events (unauthorized role changes)

---

## References

- OpenZeppelin ERC20: https://docs.openzeppelin.com/contracts/5.x/erc20
- OpenZeppelin AccessControl: https://docs.openzeppelin.com/contracts/5.x/access-control
- EIP-2612 (Permit): https://eips.ethereum.org/EIPS/eip-2612
- EIP-712 (Typed Data): https://eips.ethereum.org/EIPS/eip-712
