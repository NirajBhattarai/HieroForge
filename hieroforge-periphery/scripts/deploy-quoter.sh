#!/usr/bin/env bash
# Deploy Quoter to Hedera testnet (requires PoolManager already deployed).
# Optionally verify on HashScan when DEPLOY_AND_VERIFY=1.
#
# Usage:
#   export PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x...
#   ./scripts/deploy-quoter.sh
#
# Deploy and verify in one go:
#   DEPLOY_AND_VERIFY=1 ./scripts/deploy-quoter.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f .env ]]; then set -a; source .env; set +a; fi

# Use Foundry alias 'testnet' from foundry.toml, or RPC_URL if set
RPC_ARG="${RPC_URL:-testnet}"

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY (hex 0x...)."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi
if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
  echo "Set POOL_MANAGER_ADDRESS (deploy PoolManager from hieroforge-core first)."
  echo "  export POOL_MANAGER_ADDRESS=0x..."
  exit 1
fi

forge build

echo "Deploying Quoter (PoolManager: $POOL_MANAGER_ADDRESS)..."
DEPLOY_OUT=$(forge script script/DeployQuoter.s.sol:DeployQuoterScript \
  --rpc-url "$RPC_ARG" \
  --private-key "$PRIVATE_KEY" \
  --broadcast 2>&1)
echo "$DEPLOY_OUT"

# Parse deployed address from "Quoter: 0x..." in logs
QUOTER_ADDRESS=$(echo "$DEPLOY_OUT" | grep -oE 'Quoter: 0x[a-fA-F0-9]{40}' | head -1 | sed 's/Quoter: //')

echo ""
if [[ -z "$QUOTER_ADDRESS" ]]; then
  echo "Quoter deployed. Export the address from the log above, then:"
  echo "  export QUOTER_ADDRESS=0x..."
  echo "  ./scripts/verify-contracts.sh Quoter"
  exit 0
fi

echo "Quoter deployed at: $QUOTER_ADDRESS"
echo ""

if [[ -n "$DEPLOY_AND_VERIFY" ]]; then
  echo "Running verification (DEPLOY_AND_VERIFY=1)..."
  export QUOTER_ADDRESS
  "$SCRIPT_DIR/verify-contracts.sh" Quoter
else
  echo "To verify on HashScan:"
  echo "  export QUOTER_ADDRESS=$QUOTER_ADDRESS"
  echo "  ./scripts/verify-contracts.sh Quoter"
  echo ""
  echo "Or deploy and verify in one go next time:"
  echo "  DEPLOY_AND_VERIFY=1 ./scripts/deploy-quoter.sh"
fi
