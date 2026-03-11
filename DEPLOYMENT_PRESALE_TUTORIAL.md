# WebAI3 Presale Deployment Tutorial (Sepolia)

This tutorial is a **Sepolia-specific** deployment runbook for the modular WebAI3 presale stack:

- `WebAI3Presale`
- `PresaleVault`
- `LiquidityVault`
- `DevRunwayVault`
- `TeamStreamVault`
- `MarketingVault`
- `ClaimModule`

It is written for Foundry users and assumes deployment to:

- **Network:** Ethereum Sepolia
- **Chain ID:** `11155111`
- **Explorer:** `https://sepolia.etherscan.io`

---

## 1) Prerequisites

Install and verify:

```bash
forge --version
cast --version
jq --version
```

You also need:

- funded Sepolia deployer wallet (Sepolia ETH)
- a Sepolia USDC-compatible token address with **6 decimals**
- deployed AIC token address
- optional Etherscan API key for source verification

---

## 2) Sepolia Environment File

Create `.env.sepolia`:

```bash
cat > .env.sepolia <<'EOF_ENV'
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
PRIVATE_KEY=0xYOUR_PRIVATE_KEY
DEPLOYER=0xYOUR_DEPLOYER_ADDRESS

# Tokens on Sepolia
USDC=0xUSDC_6_DECIMALS_TOKEN
AIC_TOKEN=0xAIC_TOKEN

# Operators
PAUSER=0xPAUSER_ADDRESS
LIQUIDITY_OPERATOR=0xLIQUIDITY_OPERATOR_ADDRESS
DEV_OPERATOR=0xDEV_OPERATOR_ADDRESS
TEAM_OPERATOR=0xTEAM_OPERATOR_ADDRESS
MARKETING_OPERATOR=0xMARKETING_OPERATOR_ADDRESS

# Beneficiaries
DEV_BENEFICIARY=0xDEV_BENEFICIARY_ADDRESS
TEAM_BENEFICIARY=0xTEAM_BENEFICIARY_ADDRESS
MARKETING_BENEFICIARY=0xMARKETING_BENEFICIARY_ADDRESS

# Liquidity adapter implementing ILiquidityExecutor
LIQUIDITY_EXECUTOR=0xLIQUIDITY_EXECUTOR_ADDRESS
EOF_ENV
```

Load it:

```bash
set -a
source .env.sepolia
set +a
```

---

## 3) Sepolia Preflight Checks

### 3.1 Chain and account checks

```bash
cast chain-id --rpc-url "$SEPOLIA_RPC_URL"
# expected: 11155111

cast wallet address --private-key "$PRIVATE_KEY"
cast balance "$DEPLOYER" --rpc-url "$SEPOLIA_RPC_URL"
```

### 3.2 Token compatibility checks

```bash
cast call "$USDC" "decimals()(uint8)" --rpc-url "$SEPOLIA_RPC_URL"
# expected: 6

cast call "$AIC_TOKEN" "decimals()(uint8)" --rpc-url "$SEPOLIA_RPC_URL"
# expected: 18
```

### 3.3 Compile and test

```bash
forge build
forge test
```

---

## 4) Deployment Parameters (Sepolia)

Choose timestamps and constants:

```bash
NOW=$(date +%s)
PRESALE_START=$((NOW + 3600))                   # +1 hour
PRESALE_END=$((PRESALE_START + 120*24*60*60))  # +120 days
TGE=$((PRESALE_END + 24*60*60))                 # +1 day after presale end

TEAM_STREAM_DURATION=$((365*24*60*60))          # 365 days
MARKETING_WITHDRAW_DELAY=$((2*24*60*60))        # 2 days

# Commit liquidity strategy hash used by LiquidityVault
LIQUIDITY_PLAN_HASH=$(cast keccak "WEBAI3_LIQUIDITY_PLAN_V1_SEPOLIA")
echo "$LIQUIDITY_PLAN_HASH"
```

---

## 5) Deploy Contracts on Sepolia

Use `--chain sepolia` on all `forge create` commands.

### 5.1 LiquidityVault

```bash
LIQUIDITY_VAULT=$(forge create src/presale/LiquidityVault.sol:LiquidityVault \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$LIQUIDITY_EXECUTOR" "$LIQUIDITY_PLAN_HASH" \
  | jq -r '.deployedTo')

echo "LIQUIDITY_VAULT=$LIQUIDITY_VAULT"
```

### 5.2 DevRunwayVault

```bash
DEV_VAULT=$(forge create src/presale/DevRunwayVault.sol:DevRunwayVault \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$DEV_BENEFICIARY" "$PRESALE_START" \
  | jq -r '.deployedTo')

echo "DEV_VAULT=$DEV_VAULT"
```

### 5.3 TeamStreamVault

```bash
TEAM_VAULT=$(forge create src/presale/TeamStreamVault.sol:TeamStreamVault \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$TEAM_BENEFICIARY" "$PRESALE_START" "$TEAM_STREAM_DURATION" \
  | jq -r '.deployedTo')

echo "TEAM_VAULT=$TEAM_VAULT"
```

### 5.4 MarketingVault

```bash
MARKETING_VAULT=$(forge create src/presale/MarketingVault.sol:MarketingVault \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$MARKETING_BENEFICIARY" "$MARKETING_WITHDRAW_DELAY" \
  | jq -r '.deployedTo')

echo "MARKETING_VAULT=$MARKETING_VAULT"
```

### 5.5 PresaleVault

```bash
PRESALE_VAULT=$(forge create src/presale/PresaleVault.sol:PresaleVault \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$LIQUIDITY_VAULT" "$DEV_VAULT" "$TEAM_VAULT" "$MARKETING_VAULT" \
  | jq -r '.deployedTo')

echo "PRESALE_VAULT=$PRESALE_VAULT"
```

### 5.6 ClaimModule

```bash
CLAIM_MODULE=$(forge create src/presale/ClaimModule.sol:ClaimModule \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$AIC_TOKEN" "$TGE" \
  | jq -r '.deployedTo')

echo "CLAIM_MODULE=$CLAIM_MODULE"
```

### 5.7 WebAI3Presale

```bash
PRESALE=$(forge create src/WebAI3Presale.sol:WebAI3Presale \
  --chain sepolia \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json \
  --constructor-args "$DEPLOYER" "$USDC" "$PRESALE_VAULT" "$CLAIM_MODULE" "$PRESALE_START" "$PRESALE_END" \
  | jq -r '.deployedTo')

echo "PRESALE=$PRESALE"
```

Persist deployed addresses:

```bash
cat > deployed.sepolia.presale.env <<EOF_ADDR
LIQUIDITY_VAULT=$LIQUIDITY_VAULT
DEV_VAULT=$DEV_VAULT
TEAM_VAULT=$TEAM_VAULT
MARKETING_VAULT=$MARKETING_VAULT
PRESALE_VAULT=$PRESALE_VAULT
CLAIM_MODULE=$CLAIM_MODULE
PRESALE=$PRESALE
EOF_ADDR
```

---

## 6) One-Time Wiring

```bash
cast send "$LIQUIDITY_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$DEV_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$TEAM_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$MARKETING_VAULT" "setPresaleVault(address)" "$PRESALE_VAULT" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

cast send "$PRESALE_VAULT" "setPresale(address)" "$PRESALE" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$CLAIM_MODULE" "setPresale(address)" "$PRESALE" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

---

## 7) Grant Sepolia Operational Roles

Read role IDs from chain:

```bash
PAUSER_ROLE=$(cast call "$PRESALE" "PAUSER_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
LIQ_EXEC_ROLE=$(cast call "$LIQUIDITY_VAULT" "LIQUIDITY_EXECUTOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
DEV_ROLE=$(cast call "$DEV_VAULT" "DEV_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
TEAM_ROLE=$(cast call "$TEAM_VAULT" "TEAM_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
MARKETING_ROLE=$(cast call "$MARKETING_VAULT" "MARKETING_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
```

Grant roles:

```bash
cast send "$PRESALE" "grantRole(bytes32,address)" "$PAUSER_ROLE" "$PAUSER" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$LIQUIDITY_VAULT" "grantRole(bytes32,address)" "$LIQ_EXEC_ROLE" "$LIQUIDITY_OPERATOR" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$DEV_VAULT" "grantRole(bytes32,address)" "$DEV_ROLE" "$DEV_OPERATOR" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$TEAM_VAULT" "grantRole(bytes32,address)" "$TEAM_ROLE" "$TEAM_OPERATOR" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$MARKETING_VAULT" "grantRole(bytes32,address)" "$MARKETING_ROLE" "$MARKETING_OPERATOR" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

---

## 8) Fund ClaimModule with Presale AIC

Required amount:

- `500,000,000 * 1e18 = 500000000000000000000000000`

Transfer:

```bash
PRESALE_AIC_AMOUNT=500000000000000000000000000
cast send "$AIC_TOKEN" "transfer(address,uint256)" "$CLAIM_MODULE" "$PRESALE_AIC_AMOUNT" \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

Verify:

```bash
cast call "$AIC_TOKEN" "balanceOf(address)(uint256)" "$CLAIM_MODULE" --rpc-url "$SEPOLIA_RPC_URL"
```

---

## 9) Sepolia Post-Deploy Verification

### 9.1 Chain + wiring assertions

```bash
cast chain-id --rpc-url "$SEPOLIA_RPC_URL"  # must be 11155111

cast call "$LIQUIDITY_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$DEV_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$TEAM_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$MARKETING_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$PRESALE_VAULT" "presale()(address)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CLAIM_MODULE" "presale()(address)" --rpc-url "$SEPOLIA_RPC_URL"
```

### 9.2 Presale constants and state

```bash
cast call "$PRESALE" "HARD_CAP()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$PRESALE" "PRESALE_START_TIMESTAMP()(uint64)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$PRESALE" "PRESALE_END_TIMESTAMP()(uint64)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$PRESALE" "isFinalizable()(bool)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$PRESALE" "getPhaseInfo(uint8)(uint256,uint256,uint256,uint256,uint256)" 0 --rpc-url "$SEPOLIA_RPC_URL"
cast call "$PRESALE" "getPhaseInfo(uint8)(uint256,uint256,uint256,uint256,uint256)" 6 --rpc-url "$SEPOLIA_RPC_URL"
```

### 9.3 Liquidity/claim gates

```bash
cast call "$PRESALE_VAULT" "liquidityProvisioned()(bool)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CLAIM_MODULE" "claimsEnabled()(bool)" --rpc-url "$SEPOLIA_RPC_URL"
```

Expected before launch actions:

- `liquidityProvisioned = false`
- `claimsEnabled = false`

---

## 10) Sepolia Smoke Test (Recommended)

Use one test wallet with Sepolia USDC.

### 10.1 Buy flow

```bash
BUYER=0xBUYER_ADDRESS
BUYER_PK=0xBUYER_PRIVATE_KEY
BUY_AMOUNT=100000000   # 100 USDC, 6 decimals

cast send "$USDC" "approve(address,uint256)" "$PRESALE" "$BUY_AMOUNT" \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$BUYER_PK"

cast send "$PRESALE" "buyTokens(uint256)" "$BUY_AMOUNT" \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$BUYER_PK"
```

Check routing:

```bash
cast call "$LIQUIDITY_VAULT" "totalDeposited()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$DEV_VAULT" "totalDeposited()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$TEAM_VAULT" "totalDeposited()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$MARKETING_VAULT" "totalDeposited()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
```

---

## 11) Sepolia Go-Live Operations

### 11.1 Pause controls

```bash
cast send "$PRESALE" "pause()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$PRESALE" "unpause()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$PRESALE" "forceUnpause()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

### 11.2 Permissionless finalization

```bash
cast send "$PRESALE" "finalizePresale()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

### 11.3 Liquidity provisioning

Primary path:

```bash
cast send "$LIQUIDITY_VAULT" "provideLiquidity()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

Fallback path (after `MAX_LIQUIDITY_DELAY`):

```bash
cast send "$LIQUIDITY_VAULT" "provideLiquidityFallback()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

### 11.4 Enable claims and user claim

```bash
cast send "$CLAIM_MODULE" "enableClaims()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

cast call "$CLAIM_MODULE" "claimableAmount(address)(uint256)" "$BUYER" --rpc-url "$SEPOLIA_RPC_URL"
cast send "$CLAIM_MODULE" "claim()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$BUYER_PK"
```

---

## 12) Optional Sepolia Etherscan Verification

If you did not use `forge create --verify`, verify manually:

```bash
forge verify-contract --chain sepolia \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  "$PRESALE" src/WebAI3Presale.sol:WebAI3Presale \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint64,uint64)" "$DEPLOYER" "$USDC" "$PRESALE_VAULT" "$CLAIM_MODULE" "$PRESALE_START" "$PRESALE_END")
```

You can repeat for each deployed contract with correct constructor args.

---

## 13) Common Sepolia Failures

- `PresaleNotFinalizable`: attempted finalize before hard cap/end timestamp.
- `PhaseCapExceeded` / `HardCapExceeded`: buy too large; no partial fills.
- `LiquidityFallbackNotAvailable`: fallback provisioning called too early.
- `LiquidityNotProvisioned`: claims enabled before liquidity provisioning.
- `MarketingLocked`: attempted marketing withdrawal before finalization.
- `Allowance/Balance` failures: buyer has no Sepolia USDC or didn’t approve.

---

## 14) Security Notes (Testnet and Mainnet)

- Keep deployer and operator keys in secure signing infrastructure.
- Do not reuse testnet EOAs as mainnet privileged EOAs.
- Lock down role grants after deployment (multisig preferred).
- Treat `LIQUIDITY_EXECUTOR` and `LIQUIDITY_PLAN_HASH` as critical trust anchors.
- Perform at least one full end-to-end Sepolia rehearsal before mainnet.
