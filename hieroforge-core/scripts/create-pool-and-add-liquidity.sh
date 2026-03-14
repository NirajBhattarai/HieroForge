#!/usr/bin/env bash
# Create a pool at 1:1 price and add liquidity on testnet.
# Requires: PRIVATE_KEY, POOL_MANAGER_ADDRESS, ROUTER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS
# Optional: FEE=3000, TICK_SPACING=60. Default LIQUIDITY_DELTA=1e8 works with AMOUNT0/AMOUNT1=1e6.
# For larger liquidity set LIQUIDITY_DELTA=1e18 and AMOUNT0=AMOUNT1=6000000000000000 (~6e15 each).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env so PRIVATE_KEY, POOL_MANAGER_ADDRESS, CURRENCY0_ADDRESS, etc. are available
if [[ -f .env ]]; then set -a; source .env; set +a; fi

RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"

for key in PRIVATE_KEY POOL_MANAGER_ADDRESS ROUTER_ADDRESS CURRENCY0_ADDRESS CURRENCY1_ADDRESS; do
  if [[ -z "${!key}" ]]; then
    echo "Missing $key. Set required env vars."
    echo "  export PRIVATE_KEY=0x..."
    echo "  export POOL_MANAGER_ADDRESS=0x..."
    echo "  export ROUTER_ADDRESS=0x..."
    echo "  export CURRENCY0_ADDRESS=0x..."
    echo "  export CURRENCY1_ADDRESS=0x..."
    echo "  export AMOUNT0=6000000000000000 AMOUNT1=6000000000000000   # ~6e15 each for LIQUIDITY_DELTA=1e18"
    exit 1
  fi
done

# --ffi: required for htsSetup() when CURRENCY0/CURRENCY1 are HTS tokens (transfers go through 0x167)
# --skip-simulation: replay on Hedera RPC fails for HTS (0x167 returns 0xfe)
forge script script/CreatePoolAndAddLiquidityTestnet.s.sol:CreatePoolAndAddLiquidityTestnetScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  --ffi \
  --skip-simulation

# ── Auto-register pool in DynamoDB ──
echo ""
echo "=== Registering pool in DynamoDB ==="
UI_DIR="$(cd "$REPO_ROOT/../ui" 2>/dev/null && pwd)" || UI_DIR=""
if [[ -n "$UI_DIR" && -f "$UI_DIR/scripts/register-pool.cjs" ]]; then
  POOL_FEE="${FEE:-3000}"
  POOL_TICK_SPACING="${TICK_SPACING:-60}"
  POOL_SYM0="${SYMBOL0:-}"
  POOL_SYM1="${SYMBOL1:-}"
  node "$UI_DIR/scripts/register-pool.cjs" \
    --currency0 "$CURRENCY0_ADDRESS" \
    --currency1 "$CURRENCY1_ADDRESS" \
    --fee "$POOL_FEE" \
    --tickSpacing "$POOL_TICK_SPACING" \
    --symbol0 "$POOL_SYM0" \
    --symbol1 "$POOL_SYM1"
else
  echo "[WARN] Could not find ui/scripts/register-pool.cjs — pool not registered in DynamoDB."
  echo "Register manually: node ui/scripts/register-pool.cjs --currency0 $CURRENCY0_ADDRESS --currency1 $CURRENCY1_ADDRESS --fee 3000 --tickSpacing 60"
fi
