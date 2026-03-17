#!/usr/bin/env bash
# Deploy HieroForgeV4Position (HTS NFT, no royalties) to Hedera testnet.
#
# Prereq: .env with HEDERA_PRIVATE_KEY or PRIVATE_KEY, and POOL_MANAGER (address of PoolManager).
# Optional: OPERATOR_ACCOUNT (defaults to signer address), HTS_VALUE (default 25 ether), HTS_CREATE_GAS_LIMIT (default 2M).
#
# Usage:
#   ./scripts/deploy-hieroforge-v4-position.sh
#   RPC_URL=https://testnet.hashio.io/api ./scripts/deploy-hieroforge-v4-position.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

RPC="${RPC_URL:-https://testnet.hashio.io/api}"
KEY="${HEDERA_PRIVATE_KEY:-$PRIVATE_KEY}"

if [[ -z "$KEY" ]]; then
  echo "Error: Set HEDERA_PRIVATE_KEY or PRIVATE_KEY in .env"
  exit 1
fi

echo "[deploy] HieroForgeV4Position (HTS NFT, no royalties)..."
# Same as CreateHtsToken/CreateTwoHtsTokens: --ffi --skip-simulation; HTS create uses {gas: HTS_CREATE_GAS_LIMIT} in script
forge script script/DeployHieroForgeV4Position.s.sol:DeployHieroForgeV4Position \
  --rpc-url "$RPC" \
  --private-key "$KEY" \
  --broadcast \
  --ffi \
  --skip-simulation \
  -vv --no-block-gas-limit
