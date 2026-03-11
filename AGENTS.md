# Repository Guidelines

## Project Structure & Module Organization
- `src/`: main Solidity contracts (`WebAI3Token.sol`, `WebAI3Presale.sol`).
- `test/`: Forge tests.
- `test/WebAI3Token.t.sol`: token unit and fuzz coverage.
- `test/WebAI3Presale.t.sol` and `test/WebAI3PresalePhases.t.sol`: presale flows, boundaries, and multi-user phase behavior.
- `test/invariant/`: handler-based invariant tests for token supply/accounting.
- `script/`: deployment scripts (`DeployWebAI3Token.s.sol`).
- `lib/`: Foundry dependencies (`forge-std`, `openzeppelin-contracts`).
- `foundry.toml`: compiler, optimizer, fuzz/invariant, and formatter settings.
- Generated directories: `out/`, `cache/`, and `broadcast/` (do not edit manually).

## Build, Test, and Development Commands
- `forge build`: compile contracts with Solidity `0.8.24`.
- `forge test`: run the full test suite (unit, fuzz, invariant).
- `forge test --match-test testFuzz_`: run fuzz tests only.
- `forge test --match-path 'test/invariant/*'`: run invariant tests only.
- `forge test --match-contract WebAI3PresalePhasesTest`: run exhaustive phase advancement tests.
- `forge fmt`: apply repository formatting rules.
- `forge script script/DeployWebAI3Token.s.sol`: simulate deployment script execution.

## Coding Style & Naming Conventions
- Use 4-space indentation and keep code `forge fmt` clean before commits.
- Formatter defaults: 100-char line length, bracket spacing enabled, double quotes.
- Naming: contracts/libraries `PascalCase`, functions/variables `camelCase`, constants/errors `UPPER_SNAKE_CASE`.
- Test files must end with `.t.sol`.
- Prefer explicit test names that describe behavior, e.g. `test_InitializeRevertsOnEmptyPhases`.

## Testing Guidelines
- Keep layered coverage: unit (`test_`), fuzz (`testFuzz_`), invariants (`invariant_`).
- For contract changes, add tests for success paths, revert paths, and access control.
- For presale edits, include boundary checks around `phaseCap`, `maxTokens`, and `HARD_CAP`.
- No fixed coverage percentage is configured; the expected bar is a fully passing `forge test`.

## Commit & Pull Request Guidelines
- Match existing commit style: `<type>: <summary>` (examples in history: `feat: ...`, `test: ...`, `docs: ...`).
- Keep each commit focused on one concern and include related tests.
- PRs should include: purpose, changed contracts/files, commands run, and risk notes (roles, caps, pause/finalization paths).
- Link relevant design docs when applicable (`PRESALE_ARCHITECTURE.md`, `TECHNICAL_WEBAI3TOKEN.md`).
