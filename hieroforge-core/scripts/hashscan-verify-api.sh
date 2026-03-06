# HashScan Smart Contract Verification API helper.
# Source this file and call hashscan_api_verify.
# https://docs.hedera.com/hedera/sdks-and-apis/smart-contract-verification-api
#
# Usage: hashscan_api_verify <REPO_ROOT> <CONTRACT_NAME> <ADDRESS> [CHAIN_ID]
# Returns 0 if verification succeeded, 1 otherwise.
# Requires: jq, curl. Builds payload from metadata + all sources in metadata.sources.

hashscan_api_verify() {
  local REPO_ROOT="$1"
  local CONTRACT_NAME="$2"
  local ADDRESS="$3"
  local CHAIN_ID="${4:-296}"
  local BASE_URL="https://server-verify.hashscan.io"
  local META_FILE="$REPO_ROOT/out/$CONTRACT_NAME.sol/$CONTRACT_NAME.metadata.json"

  if [[ ! -f "$META_FILE" ]]; then
    echo "  Metadata not found: $META_FILE"
    return 1
  fi

  if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then
    echo "  HashScan API verification requires jq and curl."
    return 1
  fi

  # Build files object: all sources from metadata + metadata.json
  # For periphery: paths like hieroforge-core/... are resolved to ../hieroforge-core/src/...
  local files_json="{}"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    local content_file=""
    if [[ -f "$REPO_ROOT/$p" ]]; then
      content_file="$REPO_ROOT/$p"
    elif [[ "$p" == hieroforge-core/* ]] && [[ -f "$REPO_ROOT/../hieroforge-core/src/${p#hieroforge-core/}" ]]; then
      content_file="$REPO_ROOT/../hieroforge-core/src/${p#hieroforge-core/}"
    fi
    if [[ -n "$content_file" ]]; then
      local fragment
      fragment=$(jq -n --arg path "$p" --rawfile content "$content_file" '{($path): $content}')
      files_json=$( { echo "$files_json"; echo "$fragment"; } | jq -s '.[0] * .[1]')
    fi
  done < <(jq -r '.sources | keys[]' "$META_FILE")
  files_json=$(jq -n --argjson f "$files_json" --rawfile meta "$META_FILE" '$f + {"metadata.json": $meta}')

  local COMPILER_VERSION
  COMPILER_VERSION=$(jq -r '.compiler.version' "$META_FILE")
  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg address "$ADDRESS" \
    --arg chain "$CHAIN_ID" \
    --arg compilerVersion "$COMPILER_VERSION" \
    --arg contractName "$CONTRACT_NAME" \
    --argjson files "$files_json" \
    '{address: $address, chain: $chain, compilerVersion: $compilerVersion, contractName: $contractName, files: $files}')

  echo "  Trying POST $BASE_URL/verify..."
  local RESP BODY HTTP_CODE
  RESP=$(curl -sS -w "\n%{http_code}" -X POST "$BASE_URL/verify" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  HTTP_CODE=$(echo "$RESP" | tail -n1)
  BODY=$(echo "$RESP" | sed '$d')
  if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | jq -e '.result[0].status == "perfect" or .result[0].status == "partial"' &>/dev/null; then
      echo "  $CONTRACT_NAME verified (HashScan API)."
      echo "$BODY" | jq -r '.result[0] | "    \(.address) chain \(.chainId): \(.status) - \(.message)"'
      return 0
    fi
    if echo "$BODY" | jq -e '.result.status == "perfect" or .result.status == "partial"' &>/dev/null; then
      echo "  $CONTRACT_NAME verified (HashScan API)."
      echo "$BODY" | jq -r '.result | "    \(.address) chain \(.chainId): \(.status) - \(.message)"'
      return 0
    fi
  fi
  echo "  /verify response ($HTTP_CODE): ${BODY:0:300}"
  echo "  Trying POST $BASE_URL/verify/solc-json..."
  RESP=$(curl -sS -w "\n%{http_code}" -X POST "$BASE_URL/verify/solc-json" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  HTTP_CODE=$(echo "$RESP" | tail -n1)
  BODY=$(echo "$RESP" | sed '$d')
  if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | jq -e '.result[0].status == "perfect" or .result[0].status == "partial"' &>/dev/null; then
      echo "  $CONTRACT_NAME verified (HashScan API, solc-json)."
      echo "$BODY" | jq -r '.result[0] | "    \(.address) chain \(.chainId): \(.status) - \(.message)"'
      return 0
    fi
  fi
  echo "  /verify/solc-json response ($HTTP_CODE): ${BODY:0:200}"
  return 1
}
