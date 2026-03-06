#!/usr/bin/env bash
# Deploy (create) an HTS fungible token on Hedera testnet.
# Uses the Hedera Token Create contract; creates one token (FORGE), 1,000,000 initial supply, 4 decimals.
# Treasury receives the supply.
#
# Required: PRIVATE_KEY
# Optional: INITIAL_SUPPLY (default 1_000_000), HTS_VALUE (default 25 ether), HTS_CREATE_GAS_LIMIT (default 2M)
#
# Usage:
#   export PRIVATE_KEY=0x...
#   ./scripts/deploy-token.sh
# With custom treasury: TREASURY=0x... ./scripts/deploy-token.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env so PRIVATE_KEY, HTS_VALUE, etc. are available to forge script
if [[ -f .env ]]; then set -a; source .env; set +a; fi

RPC_URL="${RPC_URL:-https://testnet.hashio.io/api}"

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY (hex 0x...)."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

forge build

echo "Creating HTS fungible token (FORGE, treasury = signer, 1,000,000 supply, 4 decimals)..."
# --ffi: required for htsSetup() so local simulation has HTS emulation at 0x167.
# --skip-simulation: skip on-chain simulation (replay on RPC fails because Hedera returns 0xfe for eth_getCode(0x167)).
forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  --ffi \
  --skip-simulation

echo ""
echo "Done. The script prints an address from local HTS emulation (often 0x...0408); the REAL token"
echo "address is assigned by Hedera—get it from the transaction on HashScan (contract call to 0x167)."
echo "  https://hashscan.io/testnet"
echo ""
echo "If you saw INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE: use an ECDSA (EVM) Hedera account for PRIVATE_KEY"
echo "and see README 'Deploy / Create HTS token' troubleshooting."
