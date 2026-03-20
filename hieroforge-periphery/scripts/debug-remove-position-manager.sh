#!/usr/bin/env bash
# Debug remove-all/burn flow for PositionManager (tokenId).
#
# Required in .env:
#   PRIVATE_KEY, POSITION_MANAGER_ADDRESS
#
# Required env for this run:
#   TOKEN_ID (e.g. 2)
#
# Optional env:
#   MODE: 0=burn-only, 1=decrease+burn (default 1)
#   PERCENT (default 100)
#   AMOUNT0_MIN, AMOUNT1_MIN (default 0)
#   DEADLINE_SECONDS (default 3600)
#
# Usage:
#   TOKEN_ID=2 MODE=0 ./scripts/debug-remove-position-manager.sh
#   TOKEN_ID=2 MODE=1 PERCENT=100 ./scripts/debug-remove-position-manager.sh
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

RPC="${RPC_URL:-$HEDERA_TESTNET_RPC}"
KEY="${LOCAL_NODE_OPERATOR_PRIVATE_KEY:-$PRIVATE_KEY}"
export PRIVATE_KEY="${PRIVATE_KEY:-$KEY}"

export POSITION_MANAGER_ADDRESS="${POSITION_MANAGER_ADDRESS:-}"
export TOKEN_ID="${TOKEN_ID:-}"

for v in PRIVATE_KEY POSITION_MANAGER_ADDRESS TOKEN_ID; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set in .env or environment."
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  FFI_AND_SIM=""
else
  FFI_AND_SIM="--ffi --skip-simulation"
fi

echo "[debug-remove-position-manager] tokenId=$TOKEN_ID mode=${MODE:-1} percent=${PERCENT:-100}"
forge build -q
forge script script/DebugRemovePositionManager.s.sol:DebugRemovePositionManagerScript \
  --rpc-url "$RPC" \
  --private-key "$KEY" \
  --broadcast \
  $FFI_AND_SIM \
  -vvvv

echo "[debug-remove-position-manager] Done."

