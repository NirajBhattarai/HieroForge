#!/usr/bin/env bash
# Run PoolManager.initialize tests.
# Usage:
#   ./scripts/run-initialize-tests.sh              # run in-process (default)
#   ./scripts/run-initialize-tests.sh --local      # fork local Hedera node (http://localhost:7546)
#   ./scripts/run-initialize-tests.sh --testnet    # fork Hedera testnet
set -e
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--local" ]]; then
  echo "Running initialize tests forked from local Hedera node (http://localhost:7546)..."
  forge test --match-path 'test/PoolManager/initialize.t.sol' --fork-url 'http://localhost:7546' -vv "$@"
elif [[ "${1:-}" == "--testnet" ]]; then
  echo "Running initialize tests forked from Hedera testnet..."
  forge test --match-path 'test/PoolManager/initialize.t.sol' --fork-url 'https://testnet.hashio.io/api' -vv "${@:2}"
else
  echo "Running initialize tests (in-process EVM)..."
  forge test --match-path 'test/PoolManager/initialize.t.sol' -vv "$@"
fi
