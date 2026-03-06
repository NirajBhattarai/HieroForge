#!/usr/bin/env bash
# Deploy only PoolManager to Hedera testnet.
# Usage:
#   export PRIVATE_KEY=0x...
#   ./scripts/deploy-pool-manager.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env so PRIVATE_KEY etc. are available to forge script
if [[ -f .env ]]; then set -a; source .env; set +a; fi

# Use RPC URL; for Foundry use alias 'testnet' from foundry.toml if you get "Chain 296 not supported"
RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"
# Hedera Testnet chain ID (required for broadcast - Foundry may reject unknown chains otherwise)
CHAIN_ID="${CHAIN_ID:-296}"

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY (hex 0x...)."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

forge build

echo "Deploying PoolManager..."
# Try with --rpc-url alias first (testnet in foundry.toml); if you see "Chain 296 not supported",
# try: forge script ... --rpc-url "$RPC_URL" without --chain-id (or upgrade Foundry).
forge script script/DeployPoolManagerOnly.s.sol:DeployPoolManagerOnlyScript \
  --rpc-url testnet \
  --private-key "$PRIVATE_KEY" --broadcast


echo ""
echo "PoolManager deployed. Next: deploy the router with this address:"
echo "  export POOL_MANAGER_ADDRESS=<address from log above>"
echo "  ./scripts/deploy-router.sh"
