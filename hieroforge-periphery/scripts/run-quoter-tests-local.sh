#!/usr/bin/env bash
# Run Quoter tests against local Hedera node (EVM RPC at localhost:7546).
# Start your local Hiero/Hedera node first, then:
#   ./scripts/run-quoter-tests-local.sh
set -e
cd "$(dirname "$0")/.."
HEDERA_RPC_URL="${HEDERA_RPC_URL:-http://localhost:7546}"
echo "Running Quoter tests (fork: $HEDERA_RPC_URL)"
forge test --match-contract QuoterTest --fork-url "$HEDERA_RPC_URL" -v
