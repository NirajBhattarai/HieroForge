#!/usr/bin/env bash
# Transfer AMOUNT0 and AMOUNT1 to PositionManager in one tx. Run this on testnet first, then run modify.sh with SKIP_TRANSFER=1.
# Requires in .env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1.
#
# Usage:
#   ./scripts/transfer-to-position-manager.sh                              # remote testnet
#   RPC_URL=http://localhost:7546 LOCAL_HTS_EMULATION=1 ./scripts/transfer-to-position-manager.sh   # local

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

for v in POSITION_MANAGER_ADDRESS CURRENCY0_ADDRESS CURRENCY1_ADDRESS AMOUNT0 AMOUNT1; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set in .env."
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  echo "[transfer-to-pm] Local: using forge script..."
  forge build -q
  forge script script/TransferToPositionManager.s.sol:TransferToPositionManagerScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast
else
  # Testnet: forge script sees 0 balance on fork; use cast send so transfers use real on-chain balance
  echo "[transfer-to-pm] Testnet: sending two transfer txs via cast send..."
  if [[ "$AMOUNT0" -gt 0 ]]; then
    echo "[transfer-to-pm] transfer token0 -> PositionManager ($AMOUNT0)"
    cast send "$CURRENCY0_ADDRESS" "transfer(address,uint256)" "$POSITION_MANAGER_ADDRESS" "$AMOUNT0" \
      --private-key "$KEY" --rpc-url "$RPC"
  fi
  if [[ "$AMOUNT1" -gt 0 ]]; then
    echo "[transfer-to-pm] transfer token1 -> PositionManager ($AMOUNT1)"
    cast send "$CURRENCY1_ADDRESS" "transfer(address,uint256)" "$POSITION_MANAGER_ADDRESS" "$AMOUNT1" \
      --private-key "$KEY" --rpc-url "$RPC"
  fi
fi

echo "[transfer-to-pm] Done. Next: ./scripts/modify.sh"
