#!/usr/bin/env bash
# Run the Multicall Forge script for HieroForge periphery.
#
# Usage:
#   ./scripts/multicall.sh
#   RPC_URL=http://localhost:7546 ./scripts/multicall.sh
#   PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x... ./scripts/multicall.sh
#
# Requires:
#   - PRIVATE_KEY (or LOCAL_NODE_OPERATOR_PRIVATE_KEY) in .env or environment
#   - POOL_MANAGER_ADDRESS in .env or environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env if present (same pattern as deploy.sh)
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

# Default Hedera testnet RPC (same as deploy.sh)
HEDERA_TESTNET_RPC="${HEDERA_TESTNET_RPC:-https://testnet.hashio.io/api}"
RPC="${RPC_URL:-$HEDERA_TESTNET_RPC}"
KEY="${LOCAL_NODE_OPERATOR_PRIVATE_KEY:-$PRIVATE_KEY}"

if [[ -z "$KEY" ]]; then
  echo "Error: Set PRIVATE_KEY or LOCAL_NODE_OPERATOR_PRIVATE_KEY in .env or export it."
  exit 1
fi

if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
  echo "Error: POOL_MANAGER_ADDRESS not set. Run: ./scripts/deploy.sh pool-manager"
  exit 1
fi

export PRIVATE_KEY="$KEY"
export POOL_MANAGER_ADDRESS

echo "[multicall] Running MulticallScript..."
forge build -q
forge script script/Multicall.s.sol:MulticallScript \
  --rpc-url "$RPC" \
  --private-key "$KEY" \
  --broadcast --legacy -vvvv --skip-simulation

