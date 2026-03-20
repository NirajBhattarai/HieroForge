#!/usr/bin/env bash
# Remove liquidity from PositionManager for an existing TOKEN_ID.
# Supports partial remove (PERCENT<100) and full close (PERCENT=100 => decrease + burn).
#
# Required in .env:
#   PRIVATE_KEY, POSITION_MANAGER_ADDRESS
# Optional:
#   TOKEN_ID (when omitted, uses latest minted: nextTokenId - 1)
#   PERCENT (default 100), BURN_AFTER (default auto), AMOUNT0_MIN, AMOUNT1_MIN, DEADLINE_SECONDS
#
# Usage:
#   ./scripts/remove-position-manager.sh
#   TOKEN_ID=7 PERCENT=100 ./scripts/remove-position-manager.sh
#   TOKEN_ID=7 PERCENT=25 ./scripts/remove-position-manager.sh
set -e

HEDERA_TESTNET_RPC="${HEDERA_TESTNET_RPC:-https://296.rpc.thirdweb.com}"

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
export PERCENT="${PERCENT:-100}"

for v in PRIVATE_KEY POSITION_MANAGER_ADDRESS; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set in .env or shell."
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  FFI_AND_SIM=""
else
  FFI_AND_SIM="--ffi --skip-simulation"
fi

echo "[remove-position-manager] tokenId=${TOKEN_ID:-latest} percent=$PERCENT positionManager=$POSITION_MANAGER_ADDRESS"
forge build -q
forge script script/RemovePositionManager.s.sol:RemovePositionManagerScript \
  --rpc-url "$RPC" \
  --private-key "$KEY" \
  --broadcast \
  $FFI_AND_SIM

echo "[remove-position-manager] Done."
