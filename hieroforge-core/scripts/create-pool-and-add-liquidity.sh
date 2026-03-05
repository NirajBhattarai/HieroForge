#!/usr/bin/env bash
# Create a pool at 1:1 price and add liquidity on testnet.
# Requires: PRIVATE_KEY, POOL_MANAGER_ADDRESS, ROUTER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS
# Optional: FEE=3000, TICK_SPACING=60, AMOUNT0, AMOUNT1 (set both to fund router), LIQUIDITY_DELTA=1e18
# Example: AMOUNT0=1000000 AMOUNT1=1000000 ./scripts/create-pool-and-add-liquidity.sh

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
    echo "  export AMOUNT0=1000000 AMOUNT1=1000000   # to fund router for liquidity"
    exit 1
  fi
done

forge script script/CreatePoolAndAddLiquidityTestnet.s.sol:CreatePoolAndAddLiquidityTestnetScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY"
