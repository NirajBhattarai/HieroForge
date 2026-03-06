#!/usr/bin/env bash
# Deploy Counter.sol to Hedera testnet (for verification testing).
# Usage:
#   export PRIVATE_KEY=0x...
#   ./scripts/deploy-counter.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f .env ]]; then set -a; source .env; set +a; fi

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY (hex 0x...)."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

forge build

echo "Deploying Counter..."
forge script script/DeployCounter.s.sol:DeployCounterScript \
  --rpc-url testnet \
  --private-key "$PRIVATE_KEY" --broadcast

echo ""
echo "To verify (use address from above):"
echo "  ./scripts/verify-counter.sh <ADDRESS>"
echo "If programmatic verification fails, the script prepares a bundle for manual verification at https://verify.hashscan.io"
