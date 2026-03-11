# WebAI3 Presale Deployment Tutorial

This guide deploys the **modular presale system** introduced in the current architecture:

- `WebAI3Presale`
- `PresaleVault`
- `LiquidityVault`
- `DevRunwayVault`
- `TeamStreamVault`
- `MarketingVault`
- `ClaimModule`

It uses **Foundry + cast** and is written for repeatable testnet/mainnet deployment.

## 1) Prerequisites

Install:

- Foundry (`forge`, `cast`)
- `jq` (for JSON parsing in shell)

Verify:

```bash
forge --version
cast --version
jq --version
```

## 2) Environment Setup

Create `.env.presale`:

```bash
cat > .env.presale <<'EOF'
RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
PRIVATE_KEY=0xYOUR_PRIVATE_KEY
DEPLOYER=0xYOUR_DEPLOYER_ADDRESS

# Existing deployed tokens
USDC=0xUSDC_6_DECIMALS_TOKEN
AIC_TOKEN=0xAIC_TOKEN

# Ops addresses
PAUSER=0xPAUSER_ADDRESS
LIQUIDITY_OPERATOR=0xLIQUIDITY_OPERATOR_ADDRESS
DEV_OPERATOR=0xDEV_OPERATOR_ADDRESS
TEAM_OPERATOR=0xTEAM_OPERATOR_ADDRESS
MARKETING_OPERATOR=0xMARKETING_OPERATOR_ADDRESS

# Beneficiaries
DEV_BENEFICIARY=0xDEV_BENEFICIARY_ADDRESS
TEAM_BENEFICIARY=0xTEAM_BENEFICIARY_ADDRESS
MARKETING_BENEFICIARY=0xMARKETING_BENEFICIARY_ADDRESS

# Liquidity execution adapter (must implement ILiquidityExecutor)
LIQUIDITY_EXECUTOR=0xLIQUIDITY_EXECUTOR_ADDRESS
EOF
```

Load env:

```bash
set -a
source .env.presale
set +a
```

## 3) Preflight Checks

Compile and test first:

```bash
forge build
forge test
```

Check deployer:

```bash
cast wallet address --private-key "$PRIVATE_KEY"
cast balance "$DEPLOYER" --rpc-url "$RPC_URL"
```

## 4) Choose Deployment Parameters

Set timestamps and constants:

```bash
NOW=$(date +%s)
PRESALE_START=$((NOW + 3600))                  # starts in 1 hour
PRESALE_END=$((PRESALE_START + 120*24*60*60)) # 120 days
TGE=$((PRESALE_END + 24*60*60))                # +1 day

TEAM_STREAM_DURATION=$((365*24*60*60))         # 365 days
MARKETING_WITHDRAW_DELAY=$((2*24*60*60))       # 2 days

# Commit your liquidity execution plan hash (bytes32)
LIQUIDITY_PLAN_HASH=$(cast keccak "WEBAI3_LIQUIDITY_PLAN_V1")
echo "$LIQUIDITY_PLAN_HASH"
```

## 5) Deploy Contracts (Exact Order)

### 5.1 LiquidityVault

```bash
LIQUIDITY_VAULT=$(forge create src/presale/LiquidityVault.sol:LiquidityVault \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$LIQUIDITY_EXECUTOR" "$LIQUIDITY_PLAN_HASH" \
  | jq -r '.deployedTo')
echo "LIQUIDITY_VAULT=$LIQUIDITY_VAULT"
```

### 5.2 DevRunwayVault

```bash
DEV_VAULT=$(forge create src/presale/DevRunwayVault.sol:DevRunwayVault \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$DEV_BENEFICIARY" "$PRESALE_START" \
  | jq -r '.deployedTo')
echo "DEV_VAULT=$DEV_VAULT"
```

### 5.3 TeamStreamVault

```bash
TEAM_VAULT=$(forge create src/presale/TeamStreamVault.sol:TeamStreamVault \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$TEAM_BENEFICIARY" "$PRESALE_START" "$TEAM_STREAM_DURATION" \
  | jq -r '.deployedTo')
echo "TEAM_VAULT=$TEAM_VAULT"
```

### 5.4 MarketingVault

```bash
MARKETING_VAULT=$(forge create src/presale/MarketingVault.sol:MarketingVault \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$MARKETING_BENEFICIARY" "$MARKETING_WITHDRAW_DELAY" \
  | jq -r '.deployedTo')
echo "MARKETING_VAULT=$MARKETING_VAULT"
```

### 5.5 PresaleVault (router)

```bash
PRESALE_VAULT=$(forge create src/presale/PresaleVault.sol:PresaleVault \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$LIQUIDITY_VAULT" "$DEV_VAULT" "$TEAM_VAULT" "$MARKETING_VAULT" \
  | jq -r '.deployedTo')
echo "PRESALE_VAULT=$PRESALE_VAULT"
```

### 5.6 ClaimModule

```bash
CLAIM_MODULE=$(forge create src/presale/ClaimModule.sol:ClaimModule \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$AIC_TOKEN" "$TGE" \
  | jq -r '.deployedTo')
echo "CLAIM_MODULE=$CLAIM_MODULE"
```

### 5.7 WebAI3Presale

```bash
PRESALE=$(forge create src/WebAI3Presale.sol:WebAI3Presale \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$PRESALE_VAULT" "$CLAIM_MODULE" "$PRESALE_START" "$PRESALE_END" \
  | jq -r '.deployedTo')
echo "PRESALE=$PRESALE"
```

Save addresses:

```bash
cat > deployed.presale.env <<EOF
LIQUIDITY_VAULT=$LIQUIDITY_VAULT
DEV_VAULT=$DEV_VAULT
TEAM_VAULT=$TEAM_VAULT
MARKETING_VAULT=$MARKETING_VAULT
PRESALE_VAULT=$PRESALE_VAULT
CLAIM_MODULE=$CLAIM_MODULE
PRESALE=$PRESALE
EOF
```

## 6) One-Time Wiring

```bash
cast send "$LIQUIDITY_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$DEV_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$TEAM_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$MARKETING_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"

cast send "$PRESALE_VAULT" "setPresale(address)" "$PRESALE" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$CLAIM_MODULE" "setPresale(address)" "$PRESALE" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

## 7) Grant Operational Roles

Fetch role IDs from contracts (recommended, no manual hashing errors):

```bash
PAUSER_ROLE=$(cast call "$PRESALE" "PAUSER_ROLE()(bytes32)" --rpc-url "$RPC_URL")
LIQ_EXEC_ROLE=$(cast call "$LIQUIDITY_VAULT" "LIQUIDITY_EXECUTOR_ROLE()(bytes32)" --rpc-url "$RPC_URL")
DEV_ROLE=$(cast call "$DEV_VAULT" "DEV_OPERATOR_ROLE()(bytes32)" --rpc-url "$RPC_URL")
TEAM_ROLE=$(cast call "$TEAM_VAULT" "TEAM_OPERATOR_ROLE()(bytes32)" --rpc-url "$RPC_URL")
MARKETING_ROLE=$(cast call "$MARKETING_VAULT" "MARKETING_OPERATOR_ROLE()(bytes32)" --rpc-url "$RPC_URL")
```

Grant:

```bash
cast send "$PRESALE" "grantRole(bytes32,address)" "$PAUSER_ROLE" "$PAUSER" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$LIQUIDITY_VAULT" "grantRole(bytes32,address)" "$LIQ_EXEC_ROLE" "$LIQUIDITY_OPERATOR" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$DEV_VAULT" "grantRole(bytes32,address)" "$DEV_ROLE" "$DEV_OPERATOR" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$TEAM_VAULT" "grantRole(bytes32,address)" "$TEAM_ROLE" "$TEAM_OPERATOR" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$MARKETING_VAULT" "grantRole(bytes32,address)" "$MARKETING_ROLE" "$MARKETING_OPERATOR" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

## 8) Fund ClaimModule with AIC

Required amount: `500,000,000 * 1e18 = 500000000000000000000000000`.

```bash
PRESALE_AIC_AMOUNT=500000000000000000000000000
cast send "$AIC_TOKEN" "transfer(address,uint256)" "$CLAIM_MODULE" "$PRESALE_AIC_AMOUNT" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

Verify:

```bash
cast call "$AIC_TOKEN" "balanceOf(address)(uint256)" "$CLAIM_MODULE" --rpc-url "$RPC_URL"
```

## 9) Post-Deployment Verification Checklist

### 9.1 Static wiring

```bash
cast call "$LIQUIDITY_VAULT" "presaleVault()(address)" --rpc-url "$RPC_URL"
cast call "$DEV_VAULT" "presaleVault()(address)" --rpc-url "$RPC_URL"
cast call "$TEAM_VAULT" "presaleVault()(address)" --rpc-url "$RPC_URL"
cast call "$MARKETING_VAULT" "presaleVault()(address)" --rpc-url "$RPC_URL"
cast call "$PRESALE_VAULT" "presale()(address)" --rpc-url "$RPC_URL"
cast call "$CLAIM_MODULE" "presale()(address)" --rpc-url "$RPC_URL"
```

### 9.2 Presale parameters

```bash
cast call "$PRESALE" "HARD_CAP()(uint256)" --rpc-url "$RPC_URL"
cast call "$PRESALE" "PRESALE_START_TIMESTAMP()(uint64)" --rpc-url "$RPC_URL"
cast call "$PRESALE" "PRESALE_END_TIMESTAMP()(uint64)" --rpc-url "$RPC_URL"
cast call "$PRESALE" "isFinalizable()(bool)" --rpc-url "$RPC_URL"
cast call "$PRESALE" "getPhaseInfo(uint8)(uint256,uint256,uint256,uint256,uint256)" 0 --rpc-url "$RPC_URL"
cast call "$PRESALE" "getPhaseInfo(uint8)(uint256,uint256,uint256,uint256,uint256)" 6 --rpc-url "$RPC_URL"
```

### 9.3 Claims gate + liquidity gate

```bash
cast call "$CLAIM_MODULE" "claimsEnabled()(bool)" --rpc-url "$RPC_URL"
cast call "$PRESALE_VAULT" "liquidityProvisioned()(bool)" --rpc-url "$RPC_URL"
```

Expected initially:

- `claimsEnabled = false`
- `liquidityProvisioned = false`

## 10) Operational Runbook (Go-Live)

### 10.1 During sale

- Users call `buyTokens(uint256 usdcAmount)` on `WebAI3Presale`.
- USDC routes automatically via `PresaleVault` into 70/15/10/5 vault split.

### 10.2 Pause handling

Pause buys:

```bash
cast send "$PRESALE" "pause()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

Unpause:

```bash
cast send "$PRESALE" "unpause()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

Permissionless force unpause after single-pause expiry:

```bash
cast send "$PRESALE" "forceUnpause()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

### 10.3 Finalize (permissionless)

```bash
cast send "$PRESALE" "finalizePresale()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

### 10.4 Liquidity provisioning

Primary path (role-gated, before delay):

```bash
cast send "$LIQUIDITY_VAULT" "provideLiquidity()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

Fallback path (permissionless, after delay):

```bash
cast send "$LIQUIDITY_VAULT" "provideLiquidityFallback()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

### 10.5 Enable claims

Only after finalization and successful liquidity provisioning:

```bash
cast send "$CLAIM_MODULE" "enableClaims()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
```

### 10.6 User claim

User can inspect and claim:

```bash
cast call "$CLAIM_MODULE" "claimableAmount(address)(uint256)" "$ALICE" --rpc-url "$RPC_URL"
cast send "$CLAIM_MODULE" "claim()" --rpc-url "$RPC_URL" --private-key "$ALICE_PRIVATE_KEY"
```

## 11) Common Failure Cases

- `PresaleNotFinalizable`: trying to finalize before hard cap/end timestamp.
- `LiquidityFallbackNotAvailable`: fallback called before `MAX_LIQUIDITY_DELAY`.
- `LiquidityNotProvisioned`: trying to enable claims too early.
- `MarketingLocked`: marketing withdrawal attempted before finalization.
- `PhaseCapExceeded` or `HardCapExceeded`: oversized buy (no partial fill).

## 12) Security Notes for Production

- Use hardware wallets or multisig signers for operational roles.
- Verify deployed bytecode + constructor args on explorer.
- Keep `LIQUIDITY_EXECUTOR` immutable and audited.
- Keep `LIQUIDITY_PLAN_HASH` tied to an off-chain signed execution plan.
- Do a full dry run on testnet before mainnet deployment.
