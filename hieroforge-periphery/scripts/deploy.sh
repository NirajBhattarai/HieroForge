#!/usr/bin/env bash
# Deploy PoolManager (core), tokens (mock or HTS), and/or PositionManager (includes multicall). Updates .env.
# Same invocation style as verify-contracts.sh and modify.sh: run from repo, optional target.
#
# Usage:
#   ./scripts/deploy.sh [pool-manager|tokens|position-manager|router|quoter|all]
#   ./scripts/deploy.sh                    # same as 'all': full stack
#   ./scripts/deploy.sh tokens             # deploy tokens only (USE_HTS=1 for HTS)
#   ./scripts/deploy.sh quoter             # deploy Quoter only (requires POOL_MANAGER_ADDRESS)
#   USE_HTS=1 ./scripts/deploy.sh          # full stack with HTS tokens
#   RPC_URL=http://localhost:7546 ./scripts/deploy.sh
#
# Requires: PRIVATE_KEY (or LOCAL_NODE_OPERATOR_PRIVATE_KEY) in .env.
# For position-manager / quoter: POOL_MANAGER_ADDRESS must be set (run pool-manager first).
# PositionManager exposes multicall (initializePool + modifyLiquidities); use modify.sh after deploy.
# After deploy, verify with: ./scripts/verify-contracts.sh [Quoter|PositionManager|all]

set -e

# Remote Hedera testnet RPC (used when RPC_URL is not set)
HEDERA_TESTNET_RPC="${HEDERA_TESTNET_RPC:-https://testnet.hashio.io/api}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
CORE_ROOT="$(cd "$REPO_ROOT/../hieroforge-core" && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

RPC="${RPC_URL:-$HEDERA_TESTNET_RPC}"
KEY="${LOCAL_NODE_OPERATOR_PRIVATE_KEY:-$PRIVATE_KEY}"
TARGET="${1:-all}"

if [[ -z "$KEY" ]]; then
  echo "Error: Set PRIVATE_KEY or LOCAL_NODE_OPERATOR_PRIVATE_KEY in .env or export it."
  exit 1
fi

env_set() {
  local key="$1" val="$2"
  [[ -f "$REPO_ROOT/.env" ]] || touch "$REPO_ROOT/.env"
  if grep -q "^${key}=" "$REPO_ROOT/.env" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$REPO_ROOT/.env"
  else
    echo "${key}=${val}" >> "$REPO_ROOT/.env"
  fi
}

run_pool_manager() {
  echo "[deploy] Deploying PoolManager (hieroforge-core)..."
  cd "$CORE_ROOT"
  forge build -q
  OUT=$(forge script script/DeployPoolManagerOnly.s.sol:DeployPoolManagerOnlyScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast 2>&1)
  echo "$OUT"
  POOL_MANAGER_ADDRESS=$(echo "$OUT" | grep -oE 'PoolManager: 0x[a-fA-F0-9]{40}' | head -1 | sed 's/PoolManager: //')
  if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
    echo "Failed to parse POOL_MANAGER_ADDRESS from output."
    exit 1
  fi
  cd "$REPO_ROOT"
  env_set "POOL_MANAGER_ADDRESS" "$POOL_MANAGER_ADDRESS"
  echo "  POOL_MANAGER_ADDRESS=$POOL_MANAGER_ADDRESS"
}

run_tokens() {
  if [[ -n "$USE_HTS" ]]; then
    echo "[deploy] Creating HTS tokens..."
    forge build -q
    OUT=$(forge script script/CreateTwoHtsTokens.s.sol:CreateTwoHtsTokensScript \
      --rpc-url "$RPC" \
      --private-key "$KEY" \
      --broadcast \
      --ffi \
      --skip-simulation 2>&1)
    echo "$OUT"
    CURRENCY0=$(echo "$OUT" | grep 'CURRENCY0_ADDRESS (use for pool):' | sed 's/.*: *//' | tr -d ' ')
    CURRENCY1=$(echo "$OUT" | grep 'CURRENCY1_ADDRESS (use for pool):' | sed 's/.*: *//' | tr -d ' ')
    AMOUNT0=$(echo "$OUT" | grep 'AMOUNT0 (smallest unit):' | sed 's/.*: *//' | tr -d ' ')
    AMOUNT1=$(echo "$OUT" | grep 'AMOUNT1 (smallest unit):' | sed 's/.*: *//' | tr -d ' ')
    AMOUNT0="${AMOUNT0:-10000000}"
    AMOUNT1="${AMOUNT1:-10000000}"
  else
    echo "[deploy] Deploying mock ERC20 tokens..."
    forge build -q
    OUT=$(forge script script/DeployMockTokens.s.sol:DeployMockTokensScript \
      --rpc-url "$RPC" \
      --private-key "$KEY" \
      --broadcast 2>&1)
    echo "$OUT"
    CURRENCY0=$(echo "$OUT" | grep 'CURRENCY0_ADDRESS (use for pool):' | sed 's/.*: *//' | tr -d ' ')
    CURRENCY1=$(echo "$OUT" | grep 'CURRENCY1_ADDRESS (use for pool):' | sed 's/.*: *//' | tr -d ' ')
    AMOUNT0="${AMOUNT0:-1000000000000000000}"
    AMOUNT1="${AMOUNT1:-1000000000000000000}"
  fi
  if [[ -z "$CURRENCY0" ]] || [[ -z "$CURRENCY1" ]]; then
    echo "Failed to parse CURRENCY0_ADDRESS / CURRENCY1_ADDRESS."
    exit 1
  fi
  env_set "CURRENCY0_ADDRESS" "$CURRENCY0"
  env_set "CURRENCY1_ADDRESS" "$CURRENCY1"
  env_set "AMOUNT0" "$AMOUNT0"
  env_set "AMOUNT1" "$AMOUNT1"
  echo "  CURRENCY0_ADDRESS=$CURRENCY0 CURRENCY1_ADDRESS=$CURRENCY1"
}

run_position_manager() {
  if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
    echo "Error: POOL_MANAGER_ADDRESS not set. Run: ./scripts/deploy.sh pool-manager"
    exit 1
  fi
  echo "[deploy] Deploying PositionManager..."
  forge build -q
  OUT=$(forge script script/DeployPositionManager.s.sol:DeployPositionManagerScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast 2>&1)
  echo "$OUT"
  POSITION_MANAGER_ADDRESS=$(echo "$OUT" | grep -oE 'PositionManager: 0x[a-fA-F0-9]{40}' | head -1 | sed 's/PositionManager: //')
  if [[ -z "$POSITION_MANAGER_ADDRESS" ]]; then
    echo "Failed to parse POSITION_MANAGER_ADDRESS."
    exit 1
  fi
  env_set "POSITION_MANAGER_ADDRESS" "$POSITION_MANAGER_ADDRESS"
  echo "  POSITION_MANAGER_ADDRESS=$POSITION_MANAGER_ADDRESS"
}

run_quoter() {
  if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
    echo "Error: POOL_MANAGER_ADDRESS not set. Run: ./scripts/deploy.sh pool-manager"
    exit 1
  fi
  echo "[deploy] Deploying Quoter (V4Quoter)..."
  forge build -q
  OUT=$(forge script script/DeployQuoter.s.sol:DeployQuoterScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast 2>&1)
  echo "$OUT"
  QUOTER_ADDRESS=$(echo "$OUT" | grep -oE 'V4Quoter: 0x[a-fA-F0-9]{40}' | head -1 | sed 's/V4Quoter: //')
  if [[ -z "$QUOTER_ADDRESS" ]]; then
    echo "Failed to parse QUOTER_ADDRESS."
    exit 1
  fi
  env_set "QUOTER_ADDRESS" "$QUOTER_ADDRESS"
  echo "  QUOTER_ADDRESS=$QUOTER_ADDRESS"
  echo "  Verify with: ./scripts/verify-contracts.sh Quoter"
}

run_router() {
  if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
    echo "Error: POOL_MANAGER_ADDRESS not set. Run: ./scripts/deploy.sh pool-manager"
    exit 1
  fi
  if [[ -z "$POSITION_MANAGER_ADDRESS" ]]; then
    echo "Error: POSITION_MANAGER_ADDRESS not set. Run: ./scripts/deploy.sh position-manager"
    exit 1
  fi
  echo "[deploy] Deploying UniversalRouter..."
  forge build -q
  OUT=$(forge script script/DeployUniversalRouter.s.sol:DeployUniversalRouterScript \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast 2>&1)
  echo "$OUT"
  ROUTER_ADDRESS=$(echo "$OUT" | grep -oE 'UniversalRouter: 0x[a-fA-F0-9]{40}' | head -1 | sed 's/UniversalRouter: //')
  if [[ -z "$ROUTER_ADDRESS" ]]; then
    echo "Failed to parse ROUTER_ADDRESS."
    exit 1
  fi
  env_set "ROUTER_ADDRESS" "$ROUTER_ADDRESS"
  echo "  ROUTER_ADDRESS=$ROUTER_ADDRESS"
}

run_hieroforge_v4_position() {
  if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
    echo "Error: POOL_MANAGER_ADDRESS not set. Run: ./scripts/deploy.sh pool-manager"
    exit 1
  fi
  echo "[deploy] Deploying HieroForgeV4Position (HTS NFT, no royalties)..."
  forge build -q
  OUT=$(forge script script/DeployHieroForgeV4Position.s.sol:DeployHieroForgeV4Position \
    --rpc-url "$RPC" \
    --private-key "$KEY" \
    --broadcast \
    --ffi \
    --skip-simulation \
    -vv --no-block-gas-limit 2>&1)
  echo "$OUT"
  HIEROFORGE_V4_POSITION_ADDRESS=$(echo "$OUT" | grep -oE 'HieroForgeV4Position deployed at: 0x[a-fA-F0-9]{40}' | head -1 | sed 's/HieroForgeV4Position deployed at: //')
  OPERATOR_ACCOUNT=$(echo "$OUT" | grep -oE 'OPERATOR_ACCOUNT=[0x[a-fA-F0-9]{40}]' | head -1 | sed 's/OPERATOR_ACCOUNT=//')
  if [[ -z "$HIEROFORGE_V4_POSITION_ADDRESS" ]]; then
    echo "Failed to parse HIEROFORGE_V4_POSITION_ADDRESS."
    exit 1
  fi
  env_set "HIEROFORGE_V4_POSITION_ADDRESS" "$HIEROFORGE_V4_POSITION_ADDRESS"
  if [[ -n "$OPERATOR_ACCOUNT" ]]; then
    env_set "OPERATOR_ACCOUNT" "$OPERATOR_ACCOUNT"
  fi
  echo "  HIEROFORGE_V4_POSITION_ADDRESS=$HIEROFORGE_V4_POSITION_ADDRESS"
  [[ -n "$OPERATOR_ACCOUNT" ]] && echo "  OPERATOR_ACCOUNT=$OPERATOR_ACCOUNT"
}

export PRIVATE_KEY="$KEY"

case "$TARGET" in
  pool-manager)
    run_pool_manager
    ;;
  tokens)
    run_tokens
    ;;
  position-manager)
    run_position_manager
    ;;
  quoter)
    run_quoter
    ;;
  router)
    run_router
    ;;
  all)
    run_pool_manager
    run_tokens
    run_position_manager
    run_router
    run_quoter
    echo "[deploy] Done. Next: ./scripts/modify.sh to add liquidity."
    echo "  Verify contracts: ./scripts/verify-contracts.sh all"
    ;;
  contracts|no-tokens)
    run_pool_manager
    run_position_manager
    run_quoter
    run_router
    echo "[deploy] Done (no tokens). Copy .env addresses to ui and core (see ENV.md)."
    echo "  Verify contracts: ./scripts/verify-contracts.sh all"
    ;;
  hieroforge-v4-position)
    run_hieroforge_v4_position
    ;;
  *)
    echo "Usage: $0 [pool-manager|tokens|position-manager|router|quoter|all|contracts]"
    echo "  pool-manager     - deploy PoolManager (core)"
    echo "  tokens           - deploy mock ERC20 or HTS tokens (USE_HTS=1 for HTS)"
    echo "  position-manager - deploy PositionManager (requires POOL_MANAGER_ADDRESS)"
    echo "  router           - deploy UniversalRouter (requires POOL_MANAGER_ADDRESS + POSITION_MANAGER_ADDRESS)"
    echo "  quoter           - deploy Quoter/V4Quoter (requires POOL_MANAGER_ADDRESS)"
    echo "  all              - deploy full stack (default)"
    echo "  contracts        - deploy pool-manager + position-manager + quoter + router (no tokens)"
    exit 1
    ;;
esac
