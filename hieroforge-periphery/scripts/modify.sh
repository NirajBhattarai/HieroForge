#!/usr/bin/env bash
# Modify liquidity via PositionManager.multicall(): initialize pool (if needed) and add liquidity in one tx.
# Runs multicall(initializePool(poolKey, sqrtPriceX96), modifyLiquidities(mint position)). Transfer tokens to PositionManager first (script does this).
# Requires in .env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1.
#
# Usage:
#   ./scripts/modify.sh                                    # remote testnet (https://testnet.hashio.io/api)
#   RPC_URL=http://localhost:7546 LOCAL_HTS_EMULATION=1 ./scripts/modify.sh   # local Hedera

set -e

# Remote Hedera testnet RPC (used when RPC_URL is not set)
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

for v in POSITION_MANAGER_ADDRESS CURRENCY0_ADDRESS CURRENCY1_ADDRESS AMOUNT0 AMOUNT1; do
  val="${!v}"
  if [[ -z "$val" ]]; then
    echo "Error: $v not set in .env. Run ./scripts/deploy.sh first (and set token amounts)."
    exit 1
  fi
done

if [[ -n "$LOCAL_HTS_EMULATION" ]] || [[ "$RPC" == "local" ]] || [[ "$RPC" == *"localhost"* ]]; then
  export LOCAL_HTS_EMULATION=1
  FFI_AND_SIM=""
else
  FFI_AND_SIM="--ffi --skip-simulation"
  # Script balance check can see 0 on fork; skip on testnet so we don't revert before broadcast
  export SKIP_BALANCE_CHECK="${SKIP_BALANCE_CHECK:-1}"
  # On testnet, transfer in script sees 0 balance and reverts; use two-step: run transfer-to-position-manager.sh first, then modify with SKIP_TRANSFER=1
  export SKIP_TRANSFER="${SKIP_TRANSFER:-1}"
fi

echo "[modify] multicall: initializePool + modifyLiquidities (create pool and add liquidity in one tx)..."
forge build -q
forge script script/AddLiquidityPositionManager.s.sol:AddLiquidityPositionManagerScript \
  --rpc-url "$RPC" \
  --private-key "$KEY" \
  --broadcast \
  $FFI_AND_SIM

echo "[modify] Done. Pool initialized and position NFT minted (check logs for tokenId)."
