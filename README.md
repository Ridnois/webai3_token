# webai3-token

Smart contract workspace for the `webai3.protocol` token.

## Why this stack

This project uses **Foundry** as the primary smart contract workspace.

That choice is deliberate:

- **Foundry** is the current best default for Solidity-native development when fast compile/test loops, fuzzing, invariant testing, and scripting are core requirements.
- **Hardhat 3** remains a strong option when a project wants a more TypeScript-centric development and deployment environment.
- **OpenZeppelin Contracts** remains the standard audited base layer for ERC-20, permit, voting, access control, and pause functionality.

For this repo, the main job is to design and harden a token contract. That favors Foundry first:

- fast unit tests
- first-class fuzz tests
- first-class invariant tests
- Anvil for local chains
- straightforward deployment scripts

## Initial token design

The first contract is intentionally conservative:

- fixed max supply: `1,000,000,000 * 1e18`
- minted once at deployment through explicit genesis allocations
- no post-deployment minting
- `ERC20Permit` for signature approvals
- `ERC20Votes` for governance compatibility
- `Pausable` + `AccessControl` for operational safety

This gives the protocol a usable governance/payment token without introducing an avoidable mint surface.

## Project layout

- `src/WebAI3Token.sol`: token contract
- `script/DeployWebAI3Token.s.sol`: deploy script
- `test/WebAI3Token.t.sol`: unit + fuzz tests
- `test/invariant/`: invariant harness and handler

## Commands

```sh
forge build
forge test
forge test --match-test testFuzz_
forge test --match-path 'test/invariant/*'
forge fmt
```

## Notes on modern smart contract development

Current best practice is not just "write tests".

Use layers:

1. **Audited primitives**
2. **Unit tests for explicit business rules**
3. **Fuzz tests for edge coverage**
4. **Invariant tests for system properties**
5. **Deployment scripts for reproducibility**
6. **Clear separation between token policy and distribution policy**

This workspace is set up to support that flow from the start.

