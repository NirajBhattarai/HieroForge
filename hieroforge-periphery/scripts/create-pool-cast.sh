#!/usr/bin/env bash
# Create pool + add liquidity via cast send (bypasses forge simulation that sees stale balances).
# Uses PositionManager.multicall(initializePool + modifyLiquidities).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a; source "$REPO_ROOT/.env"; set +a
fi

RPC="${RPC_URL:-https://testnet.hashio.io/api}"
KEY="${PRIVATE_KEY}"
PM="${POSITION_MANAGER_ADDRESS}"
C0="${CURRENCY0_ADDRESS}"
C1="${CURRENCY1_ADDRESS}"

# Pool params
FEE="${FEE:-3000}"
TICK_SPACING="${TICK_SPACING:-60}"
HOOKS="0x0000000000000000000000000000000000000000"
SQRT_PRICE_1_1="79228162514264337593543950336"

# Mint params
TICK_LOWER="${TICK_LOWER:--120}"
TICK_UPPER="${TICK_UPPER:-120}"
LIQUIDITY="${LIQUIDITY:-100000000}"
AMOUNT0="${AMOUNT0:-10000000}"
AMOUNT1="${AMOUNT1:-10000000}"
OWNER=$(cast wallet address "$KEY")
DEADLINE="99999999999"

echo "[create-pool] PositionManager: $PM"
echo "[create-pool] currency0: $C0, currency1: $C1"
echo "[create-pool] fee=$FEE tickSpacing=$TICK_SPACING"
echo "[create-pool] owner: $OWNER"

# Step 1: Encode initializePool calldata
echo "[create-pool] Encoding initializePool..."
INIT_CALLDATA=$(cast calldata "initializePool((address,address,uint24,int24,address),uint160)" "($C0,$C1,$FEE,$TICK_SPACING,$HOOKS)" "$SQRT_PRICE_1_1")

# Step 2: Encode modifyLiquidities calldata
# actions = packed uint8(0x02) = MINT_POSITION
ACTIONS="0x02"

# mintParams[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData)
MINT_PARAM=$(cast abi-encode "f((address,address,uint24,int24,address),int24,int24,uint256,uint128,uint128,address,bytes)" "($C0,$C1,$FEE,$TICK_SPACING,$HOOKS)" "$TICK_LOWER" "$TICK_UPPER" "$LIQUIDITY" "$AMOUNT0" "$AMOUNT1" "$OWNER" "0x")

# unlockData = abi.encode(bytes actions, bytes[] mintParams)
UNLOCK_DATA=$(cast abi-encode "f(bytes,bytes[])" "$ACTIONS" "[$MINT_PARAM]")

# modifyLiquidities(bytes unlockData, uint256 deadline)
MODIFY_CALLDATA=$(cast calldata "modifyLiquidities(bytes,uint256)" "$UNLOCK_DATA" "$DEADLINE")

# Step 3: multicall(bytes[] data)
MULTICALL_CALLDATA=$(cast calldata "multicall(bytes[])" "[$INIT_CALLDATA,$MODIFY_CALLDATA]")

echo "[create-pool] Sending multicall tx (initializePool + modifyLiquidities)..."
cast send "$PM" "$MULTICALL_CALLDATA" \
  --private-key "$KEY" \
  --rpc-url "$RPC" \
  --gas-limit 5000000

echo "[create-pool] Done! Pool created and liquidity added."
echo "[create-pool] Check position: cast call $PM 'nextTokenId()(uint256)' --rpc-url $RPC"
