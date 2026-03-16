#!/usr/bin/env bash
# deploy_presale_sepolia.sh
# Full presale stack redeploy on Sepolia.
# Skips AIC token deployment (already deployed).
# Run from the webai3_token/ directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env.sepolia"
OUTPUT_FILE="$SCRIPT_DIR/deployed.sepolia.presale.env"

# ─── Colours ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${GREEN}══ $* ══${NC}"; }

# ─── 1) Load env ────────────────────────────────────────────────────────────
section "Loading environment"

[[ -f "$ENV_FILE" ]] || die ".env.sepolia not found at $ENV_FILE"

# Source the file — it contains bash arithmetic for timestamps so must be eval'd
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

# Recompute timestamps fresh (override stale values from env file)
NOW=$(date +%s)
PRESALE_START=$((NOW + 30))
PRESALE_END=$((PRESALE_START + 120 * 24 * 60 * 60))
TGE=$((PRESALE_END + 24 * 60 * 60))
TEAM_STREAM_DURATION=$((365 * 24 * 60 * 60))
MARKETING_WITHDRAW_DELAY=$((2 * 24 * 60 * 60))

info "DEPLOYER:           $DEPLOYER"
info "PRESALE_START:      $PRESALE_START ($(date -d "@$PRESALE_START" 2>/dev/null || date -r "$PRESALE_START"))"
info "PRESALE_END:        $PRESALE_END"
info "TGE:                $TGE"

# ─── 2) Prerequisites ────────────────────────────────────────────────────────
section "Checking prerequisites"

for cmd in forge cast jq; do
  command -v "$cmd" &>/dev/null || die "'$cmd' not found. Install Foundry and jq."
  info "$cmd: $(${cmd} --version 2>&1 | head -1)"
done

# ─── 3) Preflight checks ─────────────────────────────────────────────────────
section "Preflight checks"

CHAIN_ID=$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL")
[[ "$CHAIN_ID" == "11155111" ]] || die "Wrong chain: got $CHAIN_ID, expected 11155111"
info "Chain ID: $CHAIN_ID ✓"

BALANCE=$(cast balance "$DEPLOYER" --rpc-url "$SEPOLIA_RPC_URL")
info "Deployer ETH balance: $BALANCE"
[[ "$BALANCE" != "0" ]] || warn "Deployer balance is zero — transactions will fail"

USDC_DECIMALS=$(cast call "$USDC" "decimals()(uint8)" --rpc-url "$SEPOLIA_RPC_URL")
[[ "$USDC_DECIMALS" == "6" ]] || die "USDC at $USDC has $USDC_DECIMALS decimals, expected 6"
info "USDC decimals: $USDC_DECIMALS ✓"

AIC_DECIMALS=$(cast call "$AIC_TOKEN" "decimals()(uint8)" --rpc-url "$SEPOLIA_RPC_URL")
[[ "$AIC_DECIMALS" == "18" ]] || die "AIC token at $AIC_TOKEN has $AIC_DECIMALS decimals, expected 18"
info "AIC token: $AIC_TOKEN (decimals: $AIC_DECIMALS) ✓"

# ─── 4) Build ────────────────────────────────────────────────────────────────
section "Building contracts"

forge build --quiet
info "Build successful ✓"

# ─── 5) Helper: deploy contract ──────────────────────────────────────────────
deploy() {
  local label="$1"
  local src="$2"
  shift 2
  local args=("$@")

  info "Deploying $label..." >&2
  local addr
  addr=$(forge create "$src" \
    --chain sepolia \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast --json \
    --constructor-args "${args[@]}" \
    2>/dev/null \
    | jq -r '.deployedTo')

  [[ "$addr" == 0x* ]] || die "Deployment of $label failed — got: $addr"
  info "$label deployed at $addr" >&2
  echo "$addr"
}

# ─── 6) Deploy contracts ─────────────────────────────────────────────────────
section "Deploying presale contracts"

LIQUIDITY_VAULT=$(deploy "LiquidityVault" \
  "src/presale/LiquidityVault.sol:LiquidityVault" \
  "$DEPLOYER" "$USDC" "$LIQUIDITY_RECIPIENT")

DEV_VAULT=$(deploy "DevRunwayVault" \
  "src/presale/DevRunwayVault.sol:DevRunwayVault" \
  "$DEPLOYER" "$USDC" "$DEV_BENEFICIARY" "$PRESALE_START")

TEAM_VAULT=$(deploy "TeamStreamVault" \
  "src/presale/TeamStreamVault.sol:TeamStreamVault" \
  "$DEPLOYER" "$USDC" "$TEAM_BENEFICIARY" "$PRESALE_START" "$TEAM_STREAM_DURATION")

MARKETING_VAULT=$(deploy "MarketingVault" \
  "src/presale/MarketingVault.sol:MarketingVault" \
  "$DEPLOYER" "$USDC" "$MARKETING_BENEFICIARY" "$MARKETING_WITHDRAW_DELAY")

PRESALE_VAULT=$(deploy "PresaleVault" \
  "src/presale/PresaleVault.sol:PresaleVault" \
  "$DEPLOYER" "$USDC" "$LIQUIDITY_VAULT" "$DEV_VAULT" "$TEAM_VAULT" "$MARKETING_VAULT")

CLAIM_MODULE=$(deploy "ClaimModule" \
  "src/presale/ClaimModule.sol:ClaimModule" \
  "$DEPLOYER" "$AIC_TOKEN" "$TGE")

PRESALE=$(deploy "WebAI3Presale" \
  "src/WebAI3Presale.sol:WebAI3Presale" \
  "$DEPLOYER" "$USDC" "$PRESALE_VAULT" "$CLAIM_MODULE" "$PRESALE_START" "$PRESALE_END")

# ─── 7) Save addresses ───────────────────────────────────────────────────────
section "Saving deployed addresses"

cat > "$OUTPUT_FILE" <<EOF
# Deployed presale contracts — Sepolia
# Generated: $(date -u)
AIC_TOKEN=$AIC_TOKEN
LIQUIDITY_VAULT=$LIQUIDITY_VAULT
DEV_VAULT=$DEV_VAULT
TEAM_VAULT=$TEAM_VAULT
MARKETING_VAULT=$MARKETING_VAULT
PRESALE_VAULT=$PRESALE_VAULT
CLAIM_MODULE=$CLAIM_MODULE
PRESALE=$PRESALE
PRESALE_START=$PRESALE_START
PRESALE_END=$PRESALE_END
TGE=$TGE
EOF

info "Saved to $OUTPUT_FILE"

# ─── 8) One-time wiring ──────────────────────────────────────────────────────
section "Wiring contracts"

send() {
  local label="$1"; shift
  info "$label"
  cast send "$@" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --quiet
}

send "LiquidityVault.setPresaleVault"  "$LIQUIDITY_VAULT"  "setPresaleVault(address)" "$PRESALE_VAULT"
send "DevRunwayVault.setPresaleVault"  "$DEV_VAULT"        "setPresaleVault(address)" "$PRESALE_VAULT"
send "TeamStreamVault.setPresaleVault" "$TEAM_VAULT"       "setPresaleVault(address)" "$PRESALE_VAULT"
send "MarketingVault.setPresaleVault"  "$MARKETING_VAULT"  "setPresaleVault(address)" "$PRESALE_VAULT"
send "PresaleVault.setPresale"         "$PRESALE_VAULT"    "setPresale(address)"      "$PRESALE"
send "ClaimModule.setPresale"          "$CLAIM_MODULE"     "setPresale(address)"      "$PRESALE"

info "Wiring complete ✓"

# ─── 9) Grant roles ──────────────────────────────────────────────────────────
section "Granting operational roles"

PAUSER_ROLE=$(cast call "$PRESALE" "PAUSER_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
LIQ_OP_ROLE=$(cast call "$LIQUIDITY_VAULT" "LIQUIDITY_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
DEV_ROLE=$(cast call "$DEV_VAULT" "DEV_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
TEAM_ROLE=$(cast call "$TEAM_VAULT" "TEAM_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
MARKETING_ROLE=$(cast call "$MARKETING_VAULT" "MARKETING_OPERATOR_ROLE()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")

send "grantRole PAUSER_ROLE"          "$PRESALE"          "grantRole(bytes32,address)" "$PAUSER_ROLE"    "$PAUSER"
send "grantRole LIQUIDITY_OPERATOR"   "$LIQUIDITY_VAULT"  "grantRole(bytes32,address)" "$LIQ_OP_ROLE"   "$LIQUIDITY_OPERATOR"
send "grantRole DEV_OPERATOR"         "$DEV_VAULT"        "grantRole(bytes32,address)" "$DEV_ROLE"       "$DEV_OPERATOR"
send "grantRole TEAM_OPERATOR"        "$TEAM_VAULT"       "grantRole(bytes32,address)" "$TEAM_ROLE"      "$TEAM_OPERATOR"
send "grantRole MARKETING_OPERATOR"   "$MARKETING_VAULT"  "grantRole(bytes32,address)" "$MARKETING_ROLE" "$MARKETING_OPERATOR"

info "Roles granted ✓"

# ─── 10) Fund ClaimModule with presale AIC ───────────────────────────────────
section "Funding ClaimModule with 500M AIC"

PRESALE_AIC_AMOUNT=500000000000000000000000000

# cast appends "[Xe26]" annotations — strip to raw integer for comparison
strip_cast() { echo "$1" | sed 's/ \[.*\]//'; }

AIC_BALANCE_RAW=$(cast call "$AIC_TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$SEPOLIA_RPC_URL")
AIC_BALANCE=$(strip_cast "$AIC_BALANCE_RAW")
info "Deployer AIC balance: $AIC_BALANCE"

# Use python for big-int comparison (bash integers overflow at 64-bit)
python3 -c "
import sys
bal = int('$AIC_BALANCE')
need = $PRESALE_AIC_AMOUNT
if bal < need:
    print(f'Insufficient AIC: have {bal}, need {need}', file=sys.stderr)
    sys.exit(1)
"

send "Transfer 500M AIC to ClaimModule" \
  "$AIC_TOKEN" "transfer(address,uint256)" "$CLAIM_MODULE" "$PRESALE_AIC_AMOUNT"

CLAIM_AIC_RAW=$(cast call "$AIC_TOKEN" "balanceOf(address)(uint256)" "$CLAIM_MODULE" --rpc-url "$SEPOLIA_RPC_URL")
CLAIM_AIC=$(strip_cast "$CLAIM_AIC_RAW")

python3 -c "
import sys
got = int('$CLAIM_AIC')
want = $PRESALE_AIC_AMOUNT
if got != want:
    print(f'ClaimModule AIC balance mismatch: got {got}, want {want}', file=sys.stderr)
    sys.exit(1)
"
info "ClaimModule funded: $CLAIM_AIC AIC ✓"

# ─── 11) Post-deploy verification ────────────────────────────────────────────
section "Post-deploy verification"

check_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    info "$label: $got ✓"
  else
    warn "$label: got '$got', expected '$want'"
  fi
}

check_eq "Chain ID" "$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL")" "11155111"

check_eq "LiquidityVault.presaleVault" \
  "$(cast call "$LIQUIDITY_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "$PRESALE_VAULT"

check_eq "DevRunwayVault.presaleVault" \
  "$(cast call "$DEV_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "$PRESALE_VAULT"

check_eq "TeamStreamVault.presaleVault" \
  "$(cast call "$TEAM_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "$PRESALE_VAULT"

check_eq "MarketingVault.presaleVault" \
  "$(cast call "$MARKETING_VAULT" "presaleVault()(address)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "$PRESALE_VAULT"

check_eq "PresaleVault.presale" \
  "$(cast call "$PRESALE_VAULT" "presale()(address)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "$PRESALE"

check_eq "ClaimModule.presale" \
  "$(cast call "$CLAIM_MODULE" "presale()(address)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "$PRESALE"

check_eq "liquidityProvisioned" \
  "$(cast call "$PRESALE_VAULT" "liquidityProvisioned()(bool)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "false"

check_eq "claimsEnabled" \
  "$(cast call "$CLAIM_MODULE" "claimsEnabled()(bool)" --rpc-url "$SEPOLIA_RPC_URL")" \
  "false"

info "HARD_CAP:    $(cast call "$PRESALE" "HARD_CAP()(uint256)" --rpc-url "$SEPOLIA_RPC_URL")"
info "lifecycle:   $(cast call "$PRESALE" "lifecycle()(uint8)" --rpc-url "$SEPOLIA_RPC_URL")"

# ─── Done ────────────────────────────────────────────────────────────────────
section "Deployment complete"
echo ""
echo "  AIC_TOKEN:        $AIC_TOKEN"
echo "  LIQUIDITY_VAULT:  $LIQUIDITY_VAULT"
echo "  DEV_VAULT:        $DEV_VAULT"
echo "  TEAM_VAULT:       $TEAM_VAULT"
echo "  MARKETING_VAULT:  $MARKETING_VAULT"
echo "  PRESALE_VAULT:    $PRESALE_VAULT"
echo "  CLAIM_MODULE:     $CLAIM_MODULE"
echo "  PRESALE:          $PRESALE"
echo ""
info "Update .env.sepolia and webai3-admin/.env.local with new addresses above."
info "Full address list saved to: $OUTPUT_FILE"
