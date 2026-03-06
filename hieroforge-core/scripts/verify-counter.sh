#!/usr/bin/env bash
# Verify Counter.sol on Hedera (HashScan) using the Smart Contract Verification API.
# https://docs.hedera.com/hedera/sdks-and-apis/smart-contract-verification-api
#
# 1. Tries POST https://server-verify.hashscan.io/verify with metadata + source (requires jq).
# 2. If that fails, tries forge verify-contract (often fails: "error decoding response body").
# 3. Otherwise prepares a bundle for manual verification at https://verify.hashscan.io
#
# Usage:
#   export COUNTER_ADDRESS=0x...
#   ./scripts/verify-counter.sh
# Or:
#   ./scripts/verify-counter.sh 0xA072368aACC9Da17E9c9123dfA116444c4954867
#
# Prerequisites: forge build (extra_output_files = ["metadata"] in foundry.toml). For API verification, jq.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

COUNTER_ADDRESS="${1:-$COUNTER_ADDRESS}"
CHAIN_ID="${CHAIN_ID:-296}"
BASE_URL="https://server-verify.hashscan.io"

if [[ -z "$COUNTER_ADDRESS" ]]; then
  echo "Usage: ./scripts/verify-counter.sh <COUNTER_ADDRESS>"
  echo "   or: export COUNTER_ADDRESS=0x... && ./scripts/verify-counter.sh"
  exit 1
fi

# Ensure metadata is emitted
forge build --extra-output-files metadata 2>/dev/null || true

META_FILE="$REPO_ROOT/out/Counter.sol/Counter.metadata.json"
SOURCE_FILE="$REPO_ROOT/src/Counter.sol"

if [[ ! -f "$META_FILE" ]] || [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Missing $META_FILE or $SOURCE_FILE. Run: forge build --extra-output-files metadata"
  exit 1
fi

# --- 1. Hedera Verification API: POST /verify (source files + metadata) ---
# Docs: https://docs.hedera.com/hedera/sdks-and-apis/smart-contract-verification-api
if command -v jq &>/dev/null; then
  COMPILER_VERSION=$(jq -r '.compiler.version' "$META_FILE")
  echo "Trying HashScan Verification API (POST $BASE_URL/verify)..."
  PAYLOAD=$(jq -n \
    --arg address "$COUNTER_ADDRESS" \
    --arg chain "$CHAIN_ID" \
    --arg compilerVersion "$COMPILER_VERSION" \
    --arg contractName "Counter" \
    --rawfile meta "$META_FILE" \
    --rawfile src "$SOURCE_FILE" \
    '{address: $address, chain: $chain, compilerVersion: $compilerVersion, contractName: $contractName, files: {"metadata.json": $meta, "src/Counter.sol": $src}}')
  set +e
  RESP=$(curl -sS -w "\n%{http_code}" -X POST "$BASE_URL/verify" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  set -e
  HTTP_CODE=$(echo "$RESP" | tail -n1)
  BODY=$(echo "$RESP" | sed '$d')
  if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | jq -e '.result[0].status == "perfect" or .result[0].status == "partial"' &>/dev/null; then
      echo "Counter verified successfully (HashScan API)."
      echo "$BODY" | jq -r '.result[0] | "  \(.address) chain \(.chainId): \(.status) - \(.message)"'
      exit 0
    fi
    # Single result object (no array)
    if echo "$BODY" | jq -e '.result.status == "perfect" or .result.status == "partial"' &>/dev/null; then
      echo "Counter verified successfully (HashScan API)."
      echo "$BODY" | jq -r '.result | "  \(.address) chain \(.chainId): \(.status) - \(.message)"'
      exit 0
    fi
  fi
  echo "  /verify response ($HTTP_CODE): ${BODY:0:400}"
  echo ""
  # Try /verify/solc-json (same payload format per API docs)
  echo "Trying POST $BASE_URL/verify/solc-json..."
  RESP2=$(curl -sS -w "\n%{http_code}" -X POST "$BASE_URL/verify/solc-json" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  HTTP_CODE2=$(echo "$RESP2" | tail -n1)
  BODY2=$(echo "$RESP2" | sed '$d')
  if [[ "$HTTP_CODE2" == "200" ]]; then
    if echo "$BODY2" | jq -e '.result[0].status == "perfect" or .result[0].status == "partial"' &>/dev/null; then
      echo "Counter verified successfully (HashScan API, solc-json)."
      echo "$BODY2" | jq -r '.result[0] | "  \(.address) chain \(.chainId): \(.status) - \(.message)"'
      exit 0
    fi
  fi
  echo "  /verify/solc-json response ($HTTP_CODE2): ${BODY2:0:300}"
  echo ""
fi

# --- 2. forge verify-contract (Sourcify); often fails with HashScan ---
set +e
forge verify-contract \
  "$COUNTER_ADDRESS" \
  src/Counter.sol:Counter \
  --chain-id "$CHAIN_ID" \
  --verifier sourcify \
  --verifier-url "$BASE_URL" \
  --watch
r=$?
set -e
if [[ $r -eq 0 ]]; then
  echo "Counter verified successfully (forge)."
  exit 0
fi

# Fallback: prepare bundle for manual verification
echo ""
echo "Programmatic verification failed (this is common with Hedera). Use manual verification:"
echo ""

BUNDLE_DIR="$REPO_ROOT/verify-bundles/Counter"
META_FILE="$REPO_ROOT/out/Counter.sol/Counter.metadata.json"

if [[ ! -f "$META_FILE" ]]; then
  echo "  Build with metadata: forge build --extra-output-files metadata"
  forge build --extra-output-files metadata
fi

mkdir -p "$BUNDLE_DIR"
cp "$META_FILE" "$BUNDLE_DIR/metadata.json"
cp "$REPO_ROOT/src/Counter.sol" "$BUNDLE_DIR/"

echo "  1. Open: https://verify.hashscan.io"
echo "  2. Contract address: $COUNTER_ADDRESS"
echo "  3. Chain: $CHAIN_ID (testnet)"
echo "  4. Compiler: Foundry"
echo "  5. Upload:"
echo "     - metadata.json from: $BUNDLE_DIR/metadata.json"
echo "     - Counter.sol from:   $BUNDLE_DIR/Counter.sol"
echo "  6. Click Verify."
echo ""
echo "Contract page: https://hashscan.io/testnet/contract/$COUNTER_ADDRESS"
exit 1
