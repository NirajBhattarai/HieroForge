#!/usr/bin/env bash
# Mint additional supply of an HTS fungible token and optionally send to an address.
# Token must have been created with Supply Key; signer must be treasury (or have supply key).
#
# Usage:
#   export PRIVATE_KEY=0x... TOKEN_ADDRESS=0x...
#   export MINT_AMOUNT=1000
#   export MINT_TO_ADDRESS=0x...   # optional; if set, minted tokens are sent here
#   ./scripts/mint-token.sh
#
# Optional: TOKEN_DECIMALS (default 4), MINT_AMOUNT (default 1000)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f .env ]]; then set -a; source .env; set +a; fi

RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY (hex 0x...)."
  exit 1
fi
if [[ -z "$TOKEN_ADDRESS" ]]; then
  echo "Set TOKEN_ADDRESS (HTS token EVM address from deploy-token / HashScan)."
  exit 1
fi

forge build

echo "Minting token $TOKEN_ADDRESS (amount: ${MINT_AMOUNT:-1000}, to: ${MINT_TO_ADDRESS:-treasury})..."
forge script script/MintHtsToken.s.sol:MintHtsTokenScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  --ffi \
  --skip-simulation

echo "Done."
