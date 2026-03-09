# HieroForge Periphery

Periphery contracts for **HieroForge**: they help users **swap tokens** by calling the core AMM (**hieroforge-core**).

## Role

- **hieroforge-core** holds the `PoolManager`, pool state, and swap logic. It is the single source of truth for liquidity and pricing.
- **hieroforge-periphery** provides user-facing contracts (e.g. **UniversalRouter** / **V4Router** for swaps, **PositionManager** for liquidity) that:
  - Encode swap parameters and call the core `PoolManager`
  - Handle the unlock callback and settle/take flows so users can swap tokens against pools created by the core

Position NFTs use standard `approve` / `setApprovalForAll` only. EIP-712 has been removed (not supported on Hedera).

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
| Quoter tests | `forge test --match-contract QuoterTest --ffi` |
| Quoter tests vs local Hedera node | `forge test --match-contract QuoterTest --ffi --fork-url http://localhost:7546` |
| V4Router swap tests (HTS) | `forge test --match-contract V4RouterSwapTest --ffi` |
| V4Router swap tests vs local Hedera node | `forge test --match-contract V4RouterSwapTest --ffi --fork-url http://localhost:7546` |
| Format | `forge fmt`   |

## Config

`foundry.toml` matches **hieroforge-core** (Cancun EVM, via_ir, optimizer, Hedera RPC endpoints). Use the same `--rpc-url` (e.g. testnet or local) as the core when deploying or calling periphery.

## HTS and local node

Quoter tests use **MockERC20** by default so they pass without a Hedera node. To run against a **local Hedera (Hiero) node**, use:

- `forge test --match-contract QuoterTest --fork-url http://localhost:7546`
For tests that create **HTS tokens** (e.g. `htsSetup()` and `createFungibleToken`), run the HTS tests from **hieroforge-core** (e.g. `cd hieroforge-core && forge test --match-test test_addLiquidity_htsHts --ffi`). The periphery Quoter is compatible with pools that use HTS tokens created on the node.

## Scripts

Set `PRIVATE_KEY` (or `LOCAL_NODE_OPERATOR_PRIVATE_KEY` for local Hedera) in `.env` before running.

| Script | What it does |
|--------|---------------|
| `./scripts/verify-contracts.sh` | Verify Quoter / PositionManager (Multicall) on Hedera (HashScan API). Usage: `./scripts/verify-contracts.sh [Quoter\|PositionManager\|Multicall\|all]` |
| `./scripts/deploy.sh [target]` | Deploy **pool-manager** \| **tokens** \| **position-manager** (with multicall) \| **all** (default). Writes addresses/amounts to `.env`. |
| `./scripts/transfer-to-position-manager.sh` | Transfer AMOUNT0 and AMOUNT1 to PositionManager in one tx. **On testnet run this first**, then `modify.sh`. |
| `./scripts/modify.sh` | **Multicall**: initialize pool and add liquidity in one tx (initializePool + modifyLiquidities). Run after deploy. On testnet expects tokens already sent (run transfer script first). |

**Deploy full stack (testnet):**

```bash
./scripts/deploy.sh
# or explicitly:
./scripts/deploy.sh all
```

**Deploy a single step (same as verify-contracts with a target):**

```bash
./scripts/deploy.sh pool-manager
./scripts/deploy.sh tokens
./scripts/deploy.sh position-manager
```

**Deploy with HTS tokens (testnet):**

```bash
USE_HTS=1 ./scripts/deploy.sh
```

**Deploy on local Hedera:**

```bash
RPC_URL=http://localhost:7546 ./scripts/deploy.sh
```

**Modify (create pool and add liquidity via multicall, after deploy):**

On **testnet**, the add-liquidity script cannot see your real token balance during simulation, so use a **two-step flow**:

```bash
# 1) Transfer tokens to PositionManager (one tx; uses your real balance)
./scripts/transfer-to-position-manager.sh

# 2) Run multicall only (initializePool + modifyLiquidities)
./scripts/modify.sh
```

`modify.sh` on testnet sets `SKIP_TRANSFER=1` by default so it only runs the multicall. On **local Hedera** you can do both in one script run:

```bash
# Local Hedera (transfer + multicall in one run)
RPC_URL=http://localhost:7546 LOCAL_HTS_EMULATION=1 ./scripts/modify.sh
```

**Verify (including PositionManager with multicall):**

```bash
./scripts/verify-contracts.sh PositionManager
# or
./scripts/verify-contracts.sh Multicall
./scripts/verify-contracts.sh all
```

- **Local Hedera**: use an Alias ECDSA key from `hedera generate-accounts` (see [Hedera local node](https://docs.hedera.com/hedera/tutorials/local-node/how-to-set-up-a-hedera-local-node)); set `PRIVATE_KEY` or `LOCAL_NODE_OPERATOR_PRIVATE_KEY` in `.env`.
- **Testnet**: `modify.sh` uses `--ffi --skip-simulation` when not on localhost.

## Usage

1. Deploy **hieroforge-core** (PoolManager and optionally create pools).
2. Deploy periphery contracts, passing the core PoolManager address.
3. In the UI or scripts, call periphery to execute swaps; periphery will call the core to perform the swap and handle token settlement.
