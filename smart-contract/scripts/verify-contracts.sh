#!/usr/bin/env bash
# Prepare verification and print instructions for HashScan (Hedera).
# Hedera runs its own Sourcify instance (https://verify.hashscan.io). Verification
# is done by uploading source + metadata there; see:
#   https://docs.hedera.com/hedera/core-concepts/smart-contracts/verifying-smart-contracts-beta
#
# For Foundry: you need the .json artifact (metadata) and the Solidity source file(s).
# This script builds, then prints the exact files and links to verify manually.
#
# Usage:
#   POOL_MANAGER_ADDRESS=0x... ROUTER_ADDRESS=0x... ./scripts/verify-contracts.sh
# With separate deploys (chain 296):
#   POOL_MANAGER_ADDRESS=$(jq -r '.transactions[0].contractAddress' broadcast/DeployPoolManagerOnly.s.sol/296/run-latest.json)
#   ROUTER_ADDRESS=$(jq -r '.transactions[0].contractAddress' broadcast/DeployModifyLiquidityRouterOnly.s.sol/296/run-latest.json)
#   ./scripts/verify-contracts.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -z "$POOL_MANAGER_ADDRESS" || -z "$ROUTER_ADDRESS" ]]; then
  echo "Set POOL_MANAGER_ADDRESS and ROUTER_ADDRESS (deployed contract addresses)."
  echo "  export POOL_MANAGER_ADDRESS=0x..."
  echo "  export ROUTER_ADDRESS=0x..."
  exit 1
fi

forge build

echo ""
echo "=== Verify on HashScan (Hedera Sourcify) ==="
echo "Hedera uses its own Sourcify instance. Verify by uploading source + metadata at:"
echo "  https://verify.hashscan.io/"
echo "Docs: https://docs.hedera.com/hedera/core-concepts/smart-contracts/verifying-smart-contracts-beta"
echo ""

echo "--- 1. PoolManager ($POOL_MANAGER_ADDRESS) ---"
echo "Contract page: https://hashscan.io/testnet/contract/$POOL_MANAGER_ADDRESS"
echo "Files to upload (Foundry: metadata .json + Solidity source):"
echo "  - Metadata: $REPO_ROOT/out/PoolManager.sol/PoolManager.json"
echo "  - Source:   $REPO_ROOT/src/PoolManager.sol (and any imports under src/)"
echo ""

echo "--- 2. ModifyLiquidityRouter ($ROUTER_ADDRESS) ---"
echo "Contract page: https://hashscan.io/testnet/contract/$ROUTER_ADDRESS"
echo "Files to upload:"
echo "  - Metadata: $REPO_ROOT/out/ModifyLiquidityRouter.sol/ModifyLiquidityRouter.json"
echo "  - Source:   $REPO_ROOT/src/ModifyLiquidityRouter.sol (and any imports under src/)"
echo ""

echo "Steps:"
echo "  1. Open https://verify.hashscan.io/"
echo "  2. Enter contract address and select chain (Hedera Testnet / 296)."
echo "  3. Upload the metadata .json and the Solidity source file(s) for that contract."
echo "  4. For contracts with many dependencies, upload all source files under src/ or use flattened source."
echo ""
