#!/usr/bin/env bash
# Run ModifyLiquidityTestnet script to add/remove liquidity on testnet.
# Required: PRIVATE_KEY, POOL_MANAGER_ADDRESS, ROUTER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS.
# Optional: FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER, LIQUIDITY_DELTA (default 1e8), AMOUNT0, AMOUNT1, SALT.
# AMOUNT0/AMOUNT1 are in token base units; must cover what the chosen LIQUIDITY_DELTA requires (~6e15 each for 1e18 at 1:1). Default 1e8 works with 1e6 each.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env so PRIVATE_KEY, POOL_MANAGER_ADDRESS, CURRENCY0_ADDRESS, etc. are available
if [[ -f .env ]]; then set -a; source .env; set +a; fi

RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"

for key in PRIVATE_KEY POOL_MANAGER_ADDRESS ROUTER_ADDRESS CURRENCY0_ADDRESS CURRENCY1_ADDRESS; do
  if [[ -z "${!key}" ]]; then
    echo "Missing $key. Set required env vars (see README)."
    exit 1
  fi
done

# --ffi: required for htsSetup() when CURRENCY0/CURRENCY1 are HTS tokens (transfers go through 0x167)
# --skip-simulation: replay on Hedera RPC fails for HTS (0x167 returns 0xfe)
forge script script/ModifyLiquidityTestnet.s.sol:ModifyLiquidityTestnetScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  --ffi \
  --skip-simulation
