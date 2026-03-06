#!/usr/bin/env bash
# Verify Quoter (and optionally other contracts) on Hedera using the HashScan Verification API.
# https://docs.hedera.com/hedera/sdks-and-apis/smart-contract-verification-api
#
# Usage:
#   export QUOTER_ADDRESS=0x...
#   ./scripts/verify-contracts.sh [Quoter|all]
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
HEDERA_VERIFIER_URL="${HEDERA_VERIFIER_URL:-https://server-verify.hashscan.io}"
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
  all)
    if [[ -z "$QUOTER_ADDRESS" ]]; then
      echo "Error: QUOTER_ADDRESS not set."
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [Quoter|all]"
    echo "  Quoter  - verify Quoter (set QUOTER_ADDRESS)"
    echo "  all     - verify all (currently Quoter only)"
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
  echo "--- Verifying Quoter at $QUOTER_ADDRESS ---"
  NEED_MANUAL=""
  if [[ -z "$VERIFY_MANUAL" ]]; then
    set +e
    hashscan_api_verify "$REPO_ROOT" "Quoter" "$QUOTER_ADDRESS" "$CHAIN_ID" && r=0 || r=1
    if [[ $r -ne 0 ]]; then
      # Quoter constructor takes IPoolManager (address); encode if you have POOL_MANAGER_ADDRESS
      if [[ -n "$POOL_MANAGER_ADDRESS" ]]; then
        CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" "$POOL_MANAGER_ADDRESS")
        forge verify-contract \
          "$QUOTER_ADDRESS" \
          src/Quoter.sol:Quoter \
          --chain-id "$CHAIN_ID" \
          --verifier sourcify \
          --verifier-url "$HEDERA_VERIFIER_URL" \
          --constructor-args "$CONSTRUCTOR_ARGS" \
          $WATCH_FLAG
      else
        forge verify-contract \
          "$QUOTER_ADDRESS" \
          src/Quoter.sol:Quoter \
          --chain-id "$CHAIN_ID" \
          --verifier sourcify \
          --verifier-url "$HEDERA_VERIFIER_URL" \
          $WATCH_FLAG
      fi
      r=$?
    fi
    set -e
    if [[ $r -ne 0 ]]; then
      echo "Quoter programmatic verification failed; use manual verification below."
      NEED_MANUAL=1
    fi
  else
    NEED_MANUAL=1
  fi
  if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
    prepare_manual_bundle "Quoter" "src/Quoter.sol" || true
  fi
  echo ""
}

NEED_MANUAL=""
case "$CONTRACT_ARG" in
  Quoter)
    verify_quoter
    ;;
  all)
    verify_quoter
    ;;
esac

if [[ -n "$NEED_MANUAL" ]] || [[ -n "$VERIFY_MANUAL" ]]; then
  echo "--- Manual verification ---"
  echo "  1. Open https://verify.hashscan.io"
  echo "  2. Address: $QUOTER_ADDRESS, Chain: $CHAIN_ID"
  echo "  3. Upload files from verify-bundles/Quoter/"
  echo "  Contract: https://hashscan.io/testnet/contract/$QUOTER_ADDRESS"
else
  echo "Done. Quoter: https://hashscan.io/testnet/contract/$QUOTER_ADDRESS"
fi
