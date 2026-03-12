#!/usr/bin/env bash
# Transfer HTS (fungible) token from the deployer to a recipient.
# HTS tokens on Hedera expose an ERC20-like interface; this script calls transfer(to, amount).
#
# Required: recipient must associate with the token first (TOKEN_NOT_ASSOCIATED_TO_ACCOUNT otherwise).
#   Recipient runs: ./scripts/associate-hts.sh   (with their PRIVATE_KEY and HTS_TOKEN_ADDRESS)
#
# Required in .env (or env): PRIVATE_KEY, HTS_TOKEN_ADDRESS, RECIPIENT_ADDRESS, AMOUNT.
#
# Usage:
#   ./scripts/transfer-hts.sh
#   ./scripts/transfer-hts.sh <token_address> <recipient_address> <amount>   # override env
#   RPC_URL=http://localhost:7546 LOCAL_HTS_EMULATION=1 ./scripts/transfer-hts.sh   # local
#
# Example .env:
#   HTS_TOKEN_ADDRESS=0x00000000000000000000000000000000007c0638
#   RECIPIENT_ADDRESS=0x32280dfa0CCFBAD6706D754b1EA5c21E60801A4d
#   AMOUNT=10000000

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

# Optional positional overrides
if [[ $# -ge 3 ]]; then
  HTS_TOKEN_ADDRESS="$1"
  RECIPIENT_ADDRESS="$2"
  AMOUNT="$3"
fi

RPC="${RPC_URL:-$HEDERA_TESTNET_RPC}"
KEY="${LOCAL_NODE_OPERATOR_PRIVATE_KEY:-$PRIVATE_KEY}"
export PRIVATE_KEY="${PRIVATE_KEY:-$KEY}"

for v in HTS_TOKEN_ADDRESS RECIPIENT_ADDRESS AMOUNT; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set. Set in .env or pass as: $0 <token_address> <recipient_address> <amount>"
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  echo "[transfer-hts] Local: using forge script..."
  forge build -q
  forge script script/TransferHts.s.sol:TransferHtsScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast
else
  echo "[transfer-hts] Testnet: sending transfer tx via cast send..."
  if ! cast send "$HTS_TOKEN_ADDRESS" "transfer(address,uint256)" "$RECIPIENT_ADDRESS" "$AMOUNT" \
    --private-key "$KEY" --rpc-url "$RPC"; then
    echo ""
    echo "If you see TOKEN_NOT_ASSOCIATED_TO_ACCOUNT: the recipient must associate with the token first."
    echo "Recipient should run: HTS_TOKEN_ADDRESS=$HTS_TOKEN_ADDRESS PRIVATE_KEY=<recipient_key> ./scripts/associate-hts.sh"
    exit 1
  fi
fi

echo "[transfer-hts] Done. Transferred $AMOUNT of $HTS_TOKEN_ADDRESS to $RECIPIENT_ADDRESS"
