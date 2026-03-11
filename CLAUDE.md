# CLAUDE.md — webai3-token

ERC-20 governance token (AIC) for the WebAI3 platform, deployed to Ethereum. Built with Foundry and OpenZeppelin v5. The entire token supply is minted once at deployment — no post-deployment minting.

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Solidity 0.8.24 |
| Build/Test Framework | Foundry (forge, cast, anvil) |
| Standard Library | OpenZeppelin Contracts v5 |
| Testing Layers | Unit + fuzz + invariant tests |
| Deployment Target | Ethereum Mainnet & Sepolia testnet |

---

## WebAI3Token Contract

**Token Name:** WebAI3 Token
**Symbol:** AIC
**Decimals:** 18
**Max Supply:** 1,000,000,000 (1B tokens, 10^27 base units)

### Design

The token is immutable after deployment:
- All 1B tokens minted in constructor from genesis allocations
- No public `mint()` function exists
- Supports governance delegation via `ERC20Votes`
- Emergency pause mechanism via `PAUSER_ROLE`
- Gasless approvals via `ERC20Permit` (EIP-2612)

### Capabilities (OpenZeppelin)

| Feature | Base Class | Purpose |
|---|---|---|
| Transfers & Balance | `ERC20` | Standard fungible token |
| Pause Mechanism | `ERC20Pausable` | Block all transfers when paused |
| Signatures | `ERC20Permit` | Approve via signature (EIP-2612) |
| Governance | `ERC20Votes` | Delegate voting power, historical voting weights |
| Roles | `AccessControl` | Admin and pauser roles |

### Public Interface

**Roles:**
```solidity
DEFAULT_ADMIN_ROLE    // Can grant/revoke roles (includes PAUSER_ROLE initially)
PAUSER_ROLE           // Can call pause() / unpause()
```

**Admin Functions:**
```solidity
function pause() external onlyRole(PAUSER_ROLE)
function unpause() external onlyRole(PAUSER_ROLE)
```

**Token Functions (from OpenZeppelin):**
- Standard ERC-20: `transfer()`, `approve()`, `transferFrom()`, `balanceOf()`, etc.
- Voting: `delegate()`, `getVotes()`, `getPastVotes()`, `getPastTotalSupply()`
- Permit: `permit()` for gasless approvals

### Constructor

```solidity
constructor(address admin, Allocation[] memory allocations)
```

**Parameters:**
- `admin`: Address to receive `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Must not be zero.
- `allocations`: Array of `Allocation` structs defining initial token distribution.

**Allocation Struct:**
```solidity
struct Allocation {
    address recipient;  // Recipient address (must not be zero)
    uint256 amount;     // Tokens to mint (in base units, e.g., 1e18 = 1 token)
}
```

**Validation:**
- Reverts if `admin` is zero address
- Reverts if `allocations` array is empty
- Reverts if any recipient is zero address
- Reverts if total allocated != `MAX_SUPPLY` (1e27)

**Custom Errors:**
- `InvalidAdmin(address)` — admin is zero address
- `EmptyAllocations()` — no allocations array provided
- `InvalidAllocationRecipient(uint256 index)` — zero-address recipient at index
- `InvalidAllocationTotal(uint256 expected, uint256 actual)` — sum of allocations doesn't equal MAX_SUPPLY

---

## Project Layout

```
webai3-token/
├── src/
│   └── WebAI3Token.sol             # Main token contract
├── test/
│   ├── WebAI3Token.t.sol           # Unit + fuzz tests
│   └── invariant/
│       ├── WebAI3TokenHandler.t.sol      # Stateful test handler
│       └── WebAI3TokenInvariants.t.sol   # Invariant properties
├── script/
│   └── DeployWebAI3Token.s.sol     # Deployment script
├── lib/
│   ├── forge-std/                  # Forge Std library
│   └── openzeppelin-contracts/     # OpenZeppelin v5
├── foundry.toml                    # Foundry config
├── CLAUDE.md                       # This file
└── README.md                       # Design philosophy & rationale
```

---

## Development Workflow

### Setup
```bash
forge build              # Compile contracts
forge test               # Run all tests (unit + fuzz + invariant)
forge fmt                # Format Solidity code
```

### Testing
```bash
forge test               # All tests
forge test -vvv          # Verbose: show traces and logs
forge test --gas-report  # Include gas usage per function
forge test --match-test testFuzz_  # Only fuzz tests
forge test --match-path 'test/invariant/*'  # Only invariant tests
```

### Deployment (Dry-run)
```bash
forge script script/DeployWebAI3Token.s.sol  # Simulate deployment
```

### Code Quality
```bash
forge fmt               # Auto-format (runs before commits)
```

---

## Foundry Configuration

**Solidity & Compiler:**
- Version: `0.8.24`
- Optimizer: enabled (20,000 runs)

**Testing:**
- Unit/Fuzz: 1,000 runs per test
- Invariant: 256 runs, depth 64, `fail_on_revert = false`
- Gas reports: enabled for `WebAI3Token`

**Code Style (Formatter):**
- Line length: 100 characters
- Tab width: 4 spaces
- Quote style: double quotes
- Bracket spacing: enabled

**Security:**
- FFI: disabled (no external command execution)
- Filesystem permissions: none

---

## Testing Strategy

**Three-layer approach:**

| Layer | File(s) | Purpose | Coverage |
|---|---|---|---|
| **Unit & Fuzz** | `test/WebAI3Token.t.sol` | Explicit test cases + random input fuzzing | Roles, pause/unpause, transfers, permit, votes, allocation validation |
| **Invariant Handler** | `test/invariant/WebAI3TokenHandler.t.sol` | Bounded state-changing operations | Safe operations for invariant fuzzing |
| **Invariant Properties** | `test/invariant/WebAI3TokenInvariants.t.sol` | System-wide properties that must always hold | Total supply, balance sum consistency |

**Invariant Testing Approach:**
The handler constrains operations to valid scenarios, then the invariant fuzzer runs many random sequences to ensure global properties hold (e.g., sum of all balances = total supply).

---

## What NOT to Do

- **Do not add a `mint()` function** — supply is fixed at deployment via allocations
- **Do not remove `Pausable`** — emergency pause is a critical safety mechanism
- **Do not remove `AccessControl`** — role-based permissions protect critical functions
- **Do not change `MAX_SUPPLY`** — hardcoded in contract and all tests expect 1e27
- **Do not enable FFI in `foundry.toml`** — security risk and unnecessary
- **Do not manually edit `lib/openzeppelin-contracts/`** — use `forge install` or `forge update` to update dependencies
- **Do not bypass tests** — run full test suite (including invariants) before merging changes
