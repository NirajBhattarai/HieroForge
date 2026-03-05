#!/usr/bin/env bash
# Deploy only Router to Hedera testnet (requires PoolManager already deployed).
# Usage:
#   export PRIVATE_KEY=0x...
#   export POOL_MANAGER_ADDRESS=0x...
#   ./scripts/deploy-router.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env so PRIVATE_KEY, POOL_MANAGER_ADDRESS etc. are available to forge script
if [[ -f .env ]]; then set -a; source .env; set +a; fi

RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY (hex 0x...)."
  exit 1
fi
if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
  echo "Set POOL_MANAGER_ADDRESS (deploy PoolManager first: ./scripts/deploy-pool-manager.sh)."
  echo "  export POOL_MANAGER_ADDRESS=0x..."
  exit 1
fi

forge build

echo "Deploying Router (manager: $POOL_MANAGER_ADDRESS)..."
forge script script/DeployModifyLiquidityRouterOnly.s.sol:DeployModifyLiquidityRouterOnlyScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY"

echo ""
echo "Router deployed. To verify both contracts:"
echo "  export ROUTER_ADDRESS=<address from log above>"
echo "  ./scripts/verify-contracts.sh"
