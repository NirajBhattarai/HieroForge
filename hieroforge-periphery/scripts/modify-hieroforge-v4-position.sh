#!/usr/bin/env bash
# Add liquidity via HieroForgeV4Position.multicall(): initialize pool (if needed) and mint a position in one tx.
# Requires in .env: PRIVATE_KEY, HIEROFORGE_V4_POSITION_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1.
#
# Testnet recommended two-step:
#   1) ./scripts/transfer-to-hieroforge-v4-position.sh
#   2) SKIP_TRANSFER=1 ./scripts/modify-hieroforge-v4-position.sh
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

for v in HIEROFORGE_V4_POSITION_ADDRESS CURRENCY0_ADDRESS CURRENCY1_ADDRESS AMOUNT0 AMOUNT1; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set in .env."
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  FFI_AND_SIM=""
else
  FFI_AND_SIM="--ffi --skip-simulation"
  export SKIP_BALANCE_CHECK="${SKIP_BALANCE_CHECK:-1}"
  export SKIP_TRANSFER="${SKIP_TRANSFER:-1}"
fi

echo "[modify-hfv4p] multicall: initializePool + modifyLiquidities (mint position)..."
forge build -q
forge script script/AddLiquidityHieroForgeV4Position.s.sol:AddLiquidityHieroForgeV4PositionScript \
  --rpc-url "$RPC" \
  --private-key "$KEY" \
  --broadcast \
  $FFI_AND_SIM

echo "[modify-hfv4p] Done."

