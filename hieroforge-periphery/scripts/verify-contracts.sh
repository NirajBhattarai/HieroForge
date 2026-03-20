#!/usr/bin/env bash
# Verify Quoter, PositionManager (and optionally other contracts) on Hedera using the HashScan Verification API.
# https://docs.hedera.com/hedera/sdks-and-apis/smart-contract-verification-api
#
# Usage:
#   export QUOTER_ADDRESS=0x...   # for Quoter
#   export POSITION_MANAGER_ADDRESS=0x... POOL_MANAGER_ADDRESS=0x...  # for PositionManager
#   export ROUTER_ADDRESS=0x...   # for UniversalRouter (requires POOL_MANAGER_ADDRESS + POSITION_MANAGER_ADDRESS)
#   export HIEROFORGE_V4_POSITION_ADDRESS=0x... POOL_MANAGER_ADDRESS=0x... OPERATOR_ACCOUNT=0x...  # for HieroForgeV4Position
#   ./scripts/verify-contracts.sh [Quoter|PositionManager|Router|HieroForgeV4Position|Multicall|all]
#
# Prerequisites: forge build (extra_output_files = ["metadata"]). jq, curl for API verification.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi

# Source shared HashScan API helper from core (path from periphery: ../hieroforge-core/scripts)
CORE_SCRIPTS="$(cd "$SCRIPT_DIR/../.." && pwd)/hieroforge-core/scripts"
if [[ ! -f "$CORE_SCRIPTS/hashscan-verify-api.sh" ]]; then
  echo "Error: $CORE_SCRIPTS/hashscan-verify-api.sh not found. Run from HieroForge repo with hieroforge-core present."
  exit 1
fi
# shellcheck source=../hieroforge-core/scripts/hashscan-verify-api.sh
source "$CORE_SCRIPTS/hashscan-verify-api.sh"

CHAIN_ID="${CHAIN_ID:-296}"
HEDERA_VERIFIER_URL="${HEDERA_VERIFIER_URL:-https://server-verify.hashscan.io/api}"
CONTRACT_ARG="${1:-Quoter}"
WATCH_FLAG=""
[[ -n "$VERIFY_WATCH" ]] && WATCH_FLAG="--watch"

case "$CONTRACT_ARG" in
  Quoter)
    if [[ -z "$QUOTER_ADDRESS" ]]; then
      echo "Error: QUOTER_ADDRESS not set. Set it in .env or export it."
      exit 1
    fi
    ;;
  Router)
    if [[ -z "$ROUTER_ADDRESS" ]]; then
      echo "Error: ROUTER_ADDRESS not set."
      exit 1
    fi
    if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
      echo "Error: POOL_MANAGER_ADDRESS required for Router constructor args."
      exit 1
    fi
    if [[ -z "$POSITION_MANAGER_ADDRESS" ]]; then
      echo "Error: POSITION_MANAGER_ADDRESS required for Router constructor args."
      exit 1
    fi
    ;;
  PositionManager|Multicall)
    if [[ -z "$POSITION_MANAGER_ADDRESS" ]]; then
      echo "Error: POSITION_MANAGER_ADDRESS not set."
      exit 1
    fi
    if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
      echo "Error: POOL_MANAGER_ADDRESS required for PositionManager constructor args."
      exit 1
    fi
    ;;
  HieroForgeV4Position)
    if [[ -z "$HIEROFORGE_V4_POSITION_ADDRESS" ]]; then
      echo "Error: HIEROFORGE_V4_POSITION_ADDRESS not set."
      exit 1
    fi
    if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
      echo "Error: POOL_MANAGER_ADDRESS required for HieroForgeV4Position constructor."
      exit 1
    fi
    if [[ -z "$OPERATOR_ACCOUNT" ]]; then
      echo "Error: OPERATOR_ACCOUNT required for HieroForgeV4Position (use the EOA that deployed it)."
      exit 1
    fi
    ;;
  all)
    if [[ -z "$QUOTER_ADDRESS" ]]; then echo "Error: QUOTER_ADDRESS not set."; exit 1; fi
    if [[ -z "$POSITION_MANAGER_ADDRESS" ]]; then echo "Error: POSITION_MANAGER_ADDRESS not set."; exit 1; fi
    if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
      echo "Error: POOL_MANAGER_ADDRESS required for PositionManager."
      exit 1
    fi
    if [[ -z "$ROUTER_ADDRESS" ]]; then
      echo "Error: ROUTER_ADDRESS required for Router."
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [Quoter|PositionManager|Router|HieroForgeV4Position|Multicall|all]"
    echo "  Quoter              - verify Quoter (set QUOTER_ADDRESS)"
    echo "  PositionManager     - verify PositionManager (set POSITION_MANAGER_ADDRESS, POOL_MANAGER_ADDRESS)"
    echo "  Router              - verify UniversalRouter (set ROUTER_ADDRESS, POOL_MANAGER_ADDRESS, POSITION_MANAGER_ADDRESS)"
    echo "  HieroForgeV4Position - verify HieroForgeV4Position (set HIEROFORGE_V4_POSITION_ADDRESS, POOL_MANAGER_ADDRESS, OPERATOR_ACCOUNT)"
    echo "  Multicall           - same as PositionManager"
    echo "  all                 - verify Quoter + PositionManager + Router"
    exit 1
    ;;
esac

echo "Using CHAIN_ID=$CHAIN_ID"
echo "Verification: HashScan API first, then forge, then manual bundle."
echo ""

forge build --extra-output-files metadata 2>/dev/null || forge build

prepare_manual_bundle() {
  local name="$1"
  local sol_path="$2"
  local meta_file="$REPO_ROOT/out/${name}.sol/${name}.metadata.json"
  local bundle_dir="$REPO_ROOT/verify-bundles/$name"
  if [[ ! -f "$meta_file" ]]; then
    echo "  Skipping $name: $meta_file not found."
    return 1
  fi
  mkdir -p "$bundle_dir"
  cp "$meta_file" "$bundle_dir/metadata.json"
  if [[ -f "$REPO_ROOT/$sol_path" ]]; then
    cp "$REPO_ROOT/$sol_path" "$bundle_dir/"
  fi
  echo "  Prepared $bundle_dir"
  return 0
}

verify_quoter() {
  echo "--- Verifying V4Quoter at $QUOTER_ADDRESS ---"
  local need_manual=""
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "V4Quoter" "$QUOTER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      if [[ -n "$POOL_MANAGER_ADDRESS" ]]; then
        CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" "$POOL_MANAGER_ADDRESS")
        forge verify-contract \
          "$QUOTER_ADDRESS" \
          src/V4Quoter.sol:V4Quoter \
          --chain-id "$CHAIN_ID" \
          --verifier sourcify \
          --verifier-url "$HEDERA_VERIFIER_URL" \
          --constructor-args "$CONSTRUCTOR_ARGS" \
          $WATCH_FLAG
      else
        forge verify-contract \
          "$QUOTER_ADDRESS" \
          src/V4Quoter.sol:V4Quoter \
          --chain-id "$CHAIN_ID" \
          --verifier sourcify \
          --verifier-url "$HEDERA_VERIFIER_URL" \
          $WATCH_FLAG
      fi
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "V4Quoter programmatic verification failed; use manual verification below."
      need_manual=1
    fi
  else
    need_manual=1
  fi
  if [[ -n "$need_manual" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "V4Quoter" "src/V4Quoter.sol" || true
  fi
  [[ -n "$need_manual" ]] && NEED_MANUAL=1
  echo ""
}

verify_position_manager() {
  echo "--- Verifying PositionManager at $POSITION_MANAGER_ADDRESS ---"
  local need_manual=""
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "PositionManager" "$POSITION_MANAGER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" "$POOL_MANAGER_ADDRESS")
      forge verify-contract \
        "$POSITION_MANAGER_ADDRESS" \
        src/PositionManager.sol:PositionManager \
        --chain-id "$CHAIN_ID" \
        --verifier sourcify \
        --verifier-url "$HEDERA_VERIFIER_URL" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        $WATCH_FLAG
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "PositionManager programmatic verification failed; use manual verification below."
      need_manual=1
    fi
  else
    need_manual=1
  fi
  if [[ -n "$need_manual" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "PositionManager" "src/PositionManager.sol" || true
  fi
  [[ -n "$need_manual" ]] && NEED_MANUAL=1
  echo ""
}

verify_router() {
  echo "--- Verifying UniversalRouter at $ROUTER_ADDRESS ---"
  local need_manual=""
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "UniversalRouter" "$ROUTER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address)" "$POOL_MANAGER_ADDRESS" "$POSITION_MANAGER_ADDRESS")
      forge verify-contract \
        "$ROUTER_ADDRESS" \
        src/UniversalRouter.sol:UniversalRouter \
        --chain-id "$CHAIN_ID" \
        --verifier sourcify \
        --verifier-url "$HEDERA_VERIFIER_URL" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        $WATCH_FLAG
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "UniversalRouter programmatic verification failed; use manual verification below."
      need_manual=1
    fi
  else
    need_manual=1
  fi
  if [[ -n "$need_manual" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "UniversalRouter" "src/UniversalRouter.sol" || true
  fi
  [[ -n "$need_manual" ]] && NEED_MANUAL=1
  echo ""
}

verify_hieroforge_v4_position() {
  echo "--- Verifying HieroForgeV4Position at $HIEROFORGE_V4_POSITION_ADDRESS ---"
  local need_manual=""
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "HieroForgeV4Position" "$HIEROFORGE_V4_POSITION_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address)" "$POOL_MANAGER_ADDRESS" "$OPERATOR_ACCOUNT")
      forge verify-contract \
        "$HIEROFORGE_V4_POSITION_ADDRESS" \
        src/HieroForgeV4Position.sol:HieroForgeV4Position \
        --chain-id "$CHAIN_ID" \
        --verifier sourcify \
        --verifier-url "$HEDERA_VERIFIER_URL" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        $WATCH_FLAG
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "HieroForgeV4Position programmatic verification failed; use manual verification below."
      need_manual=1
    fi
  else
    need_manual=1
  fi
  if [[ -n "$need_manual" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "HieroForgeV4Position" "src/HieroForgeV4Position.sol" || true
  fi
  [[ -n "$need_manual" ]] && NEED_MANUAL=1
  echo ""
}

NEED_MANUAL=""
case "$CONTRACT_ARG" in
  Quoter)
    verify_quoter
    ;;
  Router)
    verify_router
    ;;
  PositionManager|Multicall)
    verify_position_manager
    ;;
  HieroForgeV4Position)
    verify_hieroforge_v4_position
    ;;
  all)
    verify_quoter
    verify_position_manager
    verify_router
    [[ -n "$HIEROFORGE_V4_POSITION_ADDRESS" ]] && [[ -n "$OPERATOR_ACCOUNT" ]] && verify_hieroforge_v4_position
    ;;
esac

if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
  echo "--- Manual verification ---"
  echo "  1. Open https://verify.hashscan.io"
  echo "  2. Address and Chain: $CHAIN_ID"
  echo "  3. Upload files from verify-bundles/<Contract>/"
  [[ -n "$QUOTER_ADDRESS" ]] && echo "  Quoter:         https://hashscan.io/testnet/contract/$QUOTER_ADDRESS"
  [[ -n "$POSITION_MANAGER_ADDRESS" ]] && echo "  PositionManager: https://hashscan.io/testnet/contract/$POSITION_MANAGER_ADDRESS"
  [[ -n "$ROUTER_ADDRESS" ]] && echo "  Router:         https://hashscan.io/testnet/contract/$ROUTER_ADDRESS"
  [[ -n "$HIEROFORGE_V4_POSITION_ADDRESS" ]] && echo "  HieroForgeV4Position: https://hashscan.io/testnet/contract/$HIEROFORGE_V4_POSITION_ADDRESS"
else
  echo "Done."
  [[ -n "$QUOTER_ADDRESS" ]] && echo "  Quoter: https://hashscan.io/testnet/contract/$QUOTER_ADDRESS"
  [[ -n "$POSITION_MANAGER_ADDRESS" ]] && echo "  PositionManager: https://hashscan.io/testnet/contract/$POSITION_MANAGER_ADDRESS"
  [[ -n "$ROUTER_ADDRESS" ]] && echo "  Router: https://hashscan.io/testnet/contract/$ROUTER_ADDRESS"
  [[ -n "$HIEROFORGE_V4_POSITION_ADDRESS" ]] && echo "  HieroForgeV4Position: https://hashscan.io/testnet/contract/$HIEROFORGE_V4_POSITION_ADDRESS"
fi
