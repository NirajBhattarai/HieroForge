#!/usr/bin/env bash
# Verify PoolManager (or another contract) on HashScan (Hedera).
# Usage:
#   ./script/verify.sh <CONTRACT_ADDRESS> [CHAIN_ID]
#   CHAIN_ID: 296 = testnet (default), 295 = mainnet, 297 = previewnet
#
# Example:
#   ./script/verify.sh 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
#   ./script/verify.sh 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 296

set -e

CONTRACT_ADDRESS="${1:?Usage: $0 <CONTRACT_ADDRESS> [CHAIN_ID]}"
CHAIN_ID="${2:-296}"
CONTRACT="src/PoolManager.sol:PoolManager"
VERIFIER_URL="https://server-verify.hashscan.io/"

echo "Verifying $CONTRACT at $CONTRACT_ADDRESS on chain $CHAIN_ID (Hedera)..."

forge verify-contract "$CONTRACT_ADDRESS" "$CONTRACT" \
  --chain-id "$CHAIN_ID" \
  --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  --rpc-url testnet

echo "Done. Check https://hashscan.io/ (switch to testnet if CHAIN_ID=296) and search for $CONTRACT_ADDRESS"
