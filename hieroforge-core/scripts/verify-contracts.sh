#!/usr/bin/env bash
# Verify smart contracts on Hedera (HashScan) using the Smart Contract Verification API
# (https://docs.hedera.com/hedera/sdks-and-apis/smart-contract-verification-api) and/or forge verify-contract.
#
# 1. Tries HashScan API (POST /verify and /verify/solc-json) for each contract (requires jq).
# 2. If that fails, tries forge verify-contract (Sourcify).
# 3. If that fails, prepares bundle for manual verification at https://verify.hashscan.io
#
# Prerequisites:
#   - Contract(s) deployed on Hedera Testnet (296) or Mainnet (295).
#   - .env with addresses for contracts you verify. For API: jq and curl.
#
# Usage:
#   ./scripts/verify-contracts.sh [PoolManager|Router|Counter|all]
#   Default: all (PoolManager + Router; Counter included if COUNTER_ADDRESS set).
#
# Env: POOL_MANAGER_ADDRESS, ROUTER_ADDRESS; optional: COUNTER_ADDRESS, CHAIN_ID (default 296),
#   VERIFY_WATCH=1, VERIFY_MANUAL=1 (skip programmatic, only prepare bundles).
#
# Examples:
#   ./scripts/verify-contracts.sh PoolManager
#   ./scripts/verify-contracts.sh all
#   VERIFY_MANUAL=1 ./scripts/verify-contracts.sh all

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env if present
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi

# shellcheck source=./hashscan-verify-api.sh
source "$SCRIPT_DIR/hashscan-verify-api.sh"

CHAIN_ID="${CHAIN_ID:-296}"
HEDERA_VERIFIER_URL="${HEDERA_VERIFIER_URL:-https://server-verify.hashscan.io}"
CONTRACT_ARG="${1:-all}"
WATCH_FLAG=""
[[ -n "$VERIFY_WATCH" ]] && WATCH_FLAG="--watch"
VERIFIER_KEY="${ETHERSCAN_API_KEY:-$HASHSCAN_API_KEY}"
if [[ -n "$VERIFIER_KEY" ]]; then
  USE_ETHERSCAN=1
  HASHSCAN_ETHERSCAN_URL="${HASHSCAN_ETHERSCAN_URL:-https://hashscan.io/api}"
else
  USE_ETHERSCAN=""
fi

# Require addresses only for the contracts we're verifying
case "$CONTRACT_ARG" in
  PoolManager) [[ -z "$POOL_MANAGER_ADDRESS" ]] && { echo "Error: POOL_MANAGER_ADDRESS not set."; exit 1; } ;;
  Router)      [[ -z "$ROUTER_ADDRESS" ]] && { echo "Error: ROUTER_ADDRESS not set."; exit 1; } ;;
  Counter)     [[ -z "$COUNTER_ADDRESS" ]] && { echo "Error: COUNTER_ADDRESS not set."; exit 1; } ;;
  all)
    if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then echo "Error: POOL_MANAGER_ADDRESS not set."; exit 1; fi
    if [[ -z "$ROUTER_ADDRESS" ]]; then echo "Error: ROUTER_ADDRESS not set."; exit 1; fi
    ;;
esac

echo "Using CHAIN_ID=$CHAIN_ID (Testnet=296, Mainnet=295)"
echo "Verification: HashScan API first, then forge verify-contract, then manual bundle."
echo ""

forge build --extra-output-files metadata 2>/dev/null || forge build

# Prepare verify-bundles for manual upload at https://verify.hashscan.io
prepare_manual_bundle() {
  local name="$1"
  local sol_path="$2"
  local artifact_dir="$REPO_ROOT/out/${name}.sol"
  local meta_file="$artifact_dir/${name}.metadata.json"
  local bundle_dir="$REPO_ROOT/verify-bundles/$name"
  if [[ ! -f "$meta_file" ]]; then
    echo "  Skipping $name: $meta_file not found (run forge build with extra_output_files = [\"metadata\"])"
    return 1
  fi
  mkdir -p "$bundle_dir"
  cp "$meta_file" "$bundle_dir/metadata.json"
  if [[ -f "$REPO_ROOT/$sol_path" ]]; then
    cp "$REPO_ROOT/$sol_path" "$bundle_dir/"
  fi
  echo "  Prepared $bundle_dir (metadata.json + $(basename "$sol_path"))"
  return 0
}

print_manual_instructions() {
  echo ""
  echo "--- Manual verification (Hedera HashScan) ---"
  echo "  1. Open: https://verify.hashscan.io"
  echo "  2. Enter contract address (EVM 0x...) and chain (e.g. 296 for testnet)."
  echo "  3. Choose Foundry, then upload metadata.json and .sol files from verify-bundles/<Contract>/"
  echo "  4. Click Verify."
  echo ""
  echo "Bundles prepared:"
  for dir in "$REPO_ROOT/verify-bundles"/*/; do
    [[ -d "$dir" ]] || continue
    echo "  - $dir"
  done
  echo ""
  echo "Contract pages:"
  echo "  PoolManager: https://hashscan.io/testnet/contract/$POOL_MANAGER_ADDRESS"
  echo "  Router:      https://hashscan.io/testnet/contract/$ROUTER_ADDRESS"
  [[ -n "$COUNTER_ADDRESS" ]] && echo "  Counter:     https://hashscan.io/testnet/contract/$COUNTER_ADDRESS"
  if [[ "$CHAIN_ID" == "295" ]]; then
    echo "  (mainnet)    https://hashscan.io/mainnet/contract/..."
  fi
}

verify_pool_manager() {
  echo "--- Verifying PoolManager at $POOL_MANAGER_ADDRESS ---"
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "PoolManager" "$POOL_MANAGER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      forge verify-contract \
        "$POOL_MANAGER_ADDRESS" \
        src/PoolManager.sol:PoolManager \
        --chain-id "$CHAIN_ID" \
        --verifier sourcify \
        --verifier-url "$HEDERA_VERIFIER_URL" \
        $WATCH_FLAG
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "PoolManager programmatic verification failed; use manual verification below."
      NEED_MANUAL=1
    fi
  else
    NEED_MANUAL=1
  fi
  if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "PoolManager" "src/PoolManager.sol" || true
  fi
  echo ""
}

verify_router() {
  echo "--- Verifying Router at $ROUTER_ADDRESS ---"
  if [[ -z "$VERIFY_MANUAL" ]]; then
    CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" "$POOL_MANAGER_ADDRESS")
    set +e
    hashscan_api_verify "$REPO_ROOT" "Router" "$ROUTER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      forge verify-contract \
        "$ROUTER_ADDRESS" \
        test/utils/Router.sol:Router \
        --chain-id "$CHAIN_ID" \
        --verifier sourcify \
        --verifier-url "$HEDERA_VERIFIER_URL" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        $WATCH_FLAG
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "Router programmatic verification failed; use manual verification below."
      NEED_MANUAL=1
    fi
  else
    NEED_MANUAL=1
  fi
  if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "Router" "test/utils/Router.sol" || true
  fi
  echo ""
}

verify_counter() {
  echo "--- Verifying Counter at $COUNTER_ADDRESS ---"
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "Counter" "$COUNTER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      forge verify-contract \
        "$COUNTER_ADDRESS" \
        src/Counter.sol:Counter \
        --chain-id "$CHAIN_ID" \
        --verifier sourcify \
        --verifier-url "$HEDERA_VERIFIER_URL" \
        $WATCH_FLAG
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "Counter programmatic verification failed; use manual verification below."
      NEED_MANUAL=1
    fi
  else
    NEED_MANUAL=1
  fi
  if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "Counter" "src/Counter.sol" || true
  fi
  echo ""
}

NEED_MANUAL=""
case "$CONTRACT_ARG" in
  PoolManager)
    verify_pool_manager
    ;;
  Router)
    verify_router
    ;;
  Counter)
    verify_counter
    ;;
  all)
    verify_pool_manager
    verify_router
    if [[ -n "$COUNTER_ADDRESS" ]]; then
      verify_counter
    fi
    ;;
  *)
    echo "Usage: $0 [PoolManager|Router|Counter|all]"
    echo "  PoolManager  - verify PoolManager only"
    echo "  Router       - verify Router (constructor: POOL_MANAGER_ADDRESS)"
    echo "  Counter      - verify Counter (set COUNTER_ADDRESS)"
    echo "  all          - verify PoolManager + Router (+ Counter if COUNTER_ADDRESS set)"
    echo ""
    echo "For Quoter (periphery): run ./scripts/verify-contracts.sh from hieroforge-periphery"
    exit 1
    ;;
esac

if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
  print_manual_instructions
else
  echo "Done. Check HashScan:"
  echo "  PoolManager: https://hashscan.io/testnet/contract/$POOL_MANAGER_ADDRESS"
  echo "  Router:      https://hashscan.io/testnet/contract/$ROUTER_ADDRESS"
  [[ -n "$COUNTER_ADDRESS" ]] && echo "  Counter:     https://hashscan.io/testnet/contract/$COUNTER_ADDRESS"
  if [[ "$CHAIN_ID" == "295" ]]; then
    echo "  (mainnet)    https://hashscan.io/mainnet/contract/..."
  fi
  echo "  Quoter:      run ./scripts/verify-contracts.sh from hieroforge-periphery"
fi
