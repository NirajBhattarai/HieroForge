#!/usr/bin/env bash
# Transfer AMOUNT0 and AMOUNT1 to HieroForgeV4Position. Testnet uses cast send; local uses forge script.
# Requires in .env: PRIVATE_KEY, HIEROFORGE_V4_POSITION_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1.
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

for v in HIEROFORGE_V4_POSITION_ADDRESS CURRENCY0_ADDRESS CURRENCY1_ADDRESS AMOUNT0 AMOUNT1; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set in .env."
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  echo "[transfer-to-hfv4p] Local: using forge script..."
  forge build -q
  forge script script/TransferToHieroForgeV4Position.s.sol:TransferToHieroForgeV4PositionScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast
else
  echo "[transfer-to-hfv4p] Testnet: sending two transfer txs via cast send..."
  if [[ "$AMOUNT0" -gt 0 ]]; then
    echo "[transfer-to-hfv4p] transfer token0 -> HFV4P ($AMOUNT0)"
    cast send "$CURRENCY0_ADDRESS" "transfer(address,uint256)" "$HIEROFORGE_V4_POSITION_ADDRESS" "$AMOUNT0" \
      --private-key "$KEY" --rpc-url "$RPC"
  fi
  if [[ "$AMOUNT1" -gt 0 ]]; then
    echo "[transfer-to-hfv4p] transfer token1 -> HFV4P ($AMOUNT1)"
    cast send "$CURRENCY1_ADDRESS" "transfer(address,uint256)" "$HIEROFORGE_V4_POSITION_ADDRESS" "$AMOUNT1" \
      --private-key "$KEY" --rpc-url "$RPC"
  fi
fi

echo "[transfer-to-hfv4p] Done. Next: SKIP_TRANSFER=1 ./scripts/modify-hieroforge-v4-position.sh"

