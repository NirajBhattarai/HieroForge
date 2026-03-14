#!/usr/bin/env bash
# Associate the signer's account with an HTS token so they can receive it.
# On Hedera, an account must "associate" (opt in) with a token before it can hold it.
# The transaction must be signed by the account that will receive the token (the recipient).
#
# Required in .env or env: PRIVATE_KEY (recipient's key), HTS_TOKEN_ADDRESS.
#
# Usage (recipient runs this once per token before receiving transfers):
#   ./scripts/associate-hts.sh
#   ./scripts/associate-hts.sh <token_address>   # override HTS_TOKEN_ADDRESS
#   RPC_URL=http://localhost:7546 ./scripts/associate-hts.sh
#
# After this, the sender can run ./scripts/transfer-hts.sh to send tokens to this recipient.

set -e

HEDERA_TESTNET_RPC="${HEDERA_TESTNET_RPC:-https://testnet.hashio.io/api}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

[[ $# -ge 1 ]] && HTS_TOKEN_ADDRESS="$1"

RPC="${RPC_URL:-$HEDERA_TESTNET_RPC}"
KEY="${LOCAL_NODE_OPERATOR_PRIVATE_KEY:-$PRIVATE_KEY}"
KEY="${PRIVATE_KEY:-$KEY}"

if [[ -z "$HTS_TOKEN_ADDRESS" ]]; then
  echo "Error: HTS_TOKEN_ADDRESS not set. Set in .env or pass as: $0 <token_address>"
  exit 1
fi

if [[ -z "$KEY" ]]; then
  echo "Error: PRIVATE_KEY not set (use the recipient's key so their account is associated)."
  exit 1
fi

# Show which account will be associated (the signer, not RECIPIENT_ADDRESS from .env)
ACCOUNT=$(cast wallet address "$KEY" 2>/dev/null || true)
if [[ -n "$ACCOUNT" ]]; then
  echo "[associate-hts] Will associate this account (signer): $ACCOUNT"
  echo "[associate-hts] If you want to associate RECIPIENT_ADDRESS instead, run this script with RECIPIENT's PRIVATE_KEY."
fi

echo "[associate-hts] Associating account with token $HTS_TOKEN_ADDRESS on $RPC ..."
cast send "$HTS_TOKEN_ADDRESS" "associate()" \
  --private-key "$KEY" --rpc-url "$RPC"

echo "[associate-hts] Done. This account can now receive the token. Sender can run: ./scripts/transfer-hts.sh"
