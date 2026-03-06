# HieroForge Periphery

Periphery contracts for **HieroForge**: they help users **swap tokens** by calling the core AMM (**hieroforge-core**).

## Role

- **hieroforge-core** holds the `PoolManager`, pool state, and swap logic. It is the single source of truth for liquidity and pricing.
- **hieroforge-periphery** provides user-facing contracts (e.g. swap routers) that:
  - Encode swap parameters and call the core `PoolManager`
  - Handle the unlock callback and settle/take flows so users can swap tokens against pools created by the core

Deploy **hieroforge-core** first (PoolManager and any pools). Then deploy periphery contracts that point at the core’s PoolManager address. The UI or scripts should use periphery to perform token swaps.

## Setup

Same toolchain and libs as the core:

- [Foundry](https://getfoundry.sh/) (Forge, Cast, Anvil)
- From repo root, init submodules once: `git submodule update --init --recursive`

## Commands

| What   | Command |
|--------|--------|
| Build  | `forge build` |
| Test   | `forge test` |
| Quoter tests | `forge test --match-contract QuoterTest` |
| Quoter tests vs local Hedera node | `./scripts/run-quoter-tests-local.sh` or `forge test --match-contract QuoterTest --fork-url http://localhost:7546` |
| Format | `forge fmt`   |

## Config

`foundry.toml` matches **hieroforge-core** (Cancun EVM, via_ir, optimizer, Hedera RPC endpoints). Use the same `--rpc-url` (e.g. testnet or local) as the core when deploying or calling periphery.

## HTS and local node

Quoter tests use **MockERC20** by default so they pass without a Hedera node. To run against a **local Hedera (Hiero) node**, use:

- `forge test --match-contract QuoterTest --fork-url http://localhost:7546`
- Or: `./scripts/run-quoter-tests-local.sh`

For tests that create **HTS tokens** (e.g. `htsSetup()` and `createFungibleToken`), run the HTS tests from **hieroforge-core** (e.g. `cd hieroforge-core && forge test --match-test test_addLiquidity_htsHts --ffi`). The periphery Quoter is compatible with pools that use HTS tokens created on the node.

## Usage

1. Deploy **hieroforge-core** (PoolManager and optionally create pools).
2. Deploy periphery contracts, passing the core PoolManager address.
3. In the UI or scripts, call periphery to execute swaps; periphery will call the core to perform the swap and handle token settlement.
