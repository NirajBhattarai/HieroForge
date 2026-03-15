#!/usr/bin/env bash
# Deploy the full hook infrastructure to Hedera testnet:
#   PoolManager + HookDeployer + TWAPOracleHook (CREATE2) + Router
#   Then: create pool with hook → add liquidity → test swap → query TWAP
#
# Prerequisites:
#   - Foundry installed (forge)
#   - PRIVATE_KEY set (funded with HBAR on testnet)
#   - Two HTS tokens already created (CURRENCY0_ADDRESS, CURRENCY1_ADDRESS)
#
# Usage:
#   export PRIVATE_KEY=0x...
#   export CURRENCY0_ADDRESS=0x00000000000000000000000000000000007b4Ff0
#   export CURRENCY1_ADDRESS=0x00000000000000000000000000000000007b4ff9
#   ./scripts/deploy-hooks-testnet.sh
#
# Optional overrides:
#   export FEE=3000 TICK_SPACING=60 AMOUNT0=1000000 AMOUNT1=1000000

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env
if [[ -f .env ]]; then set -a; source .env; set +a; fi

RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"

# Validate required env
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "ERROR: Set PRIVATE_KEY (hex 0x...)."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

if [[ -z "$CURRENCY0_ADDRESS" || -z "$CURRENCY1_ADDRESS" ]]; then
  echo "ERROR: Set CURRENCY0_ADDRESS and CURRENCY1_ADDRESS."
  echo "  export CURRENCY0_ADDRESS=0x..."
  echo "  export CURRENCY1_ADDRESS=0x..."
  echo ""
  echo "Create tokens first with: ./scripts/deploy-token.sh"
  exit 1
fi

echo "=== HieroForge Hook Deployment ==="
echo "RPC: $RPC_URL"
echo "Token0: $CURRENCY0_ADDRESS"
echo "Token1: $CURRENCY1_ADDRESS"
echo ""

# Build first
echo "Building contracts..."
forge build

echo ""
echo "Deploying hooks infrastructure..."
forge script script/DeployHooksTestnet.s.sol:DeployHooksTestnetScript \
  --rpc-url testnet \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvv

echo ""
echo "=== Deployment complete! ==="
echo "Check the logs above for deployed addresses."
echo "Broadcast artifacts saved in broadcast/DeployHooksTestnet.s.sol/"
