# HieroForge Smart Contracts

Uniswap v4–style concentrated liquidity AMM (PoolManager + ModifyLiquidityRouter) and HTS token creation for **Hedera Testnet**. Built with [Foundry](https://book.getfoundry.sh/).

### Hedera forking (HTS emulation)

Scripts that call the **Hedera Token Service (HTS)** precompile (create token, modify liquidity with HTS tokens) use [**hedera-forking**](https://github.com/hashgraph/hedera-forking) so that local runs don’t hit `InvalidFEOpcode` (Hedera RPC returns `0xfe` for `eth_getCode(0x167)`). The library deploys an HTS emulation at `0x167` via `htsSetup()` and requires `--ffi`; when broadcasting we use `--skip-simulation`. **To learn how HTS emulation and fork testing work**, read the hedera-forking README: **[github.com/hashgraph/hedera-forking](https://github.com/hashgraph/hedera-forking)** — it covers setup, Foundry usage, supported HTS methods, and the Hardhat plugin.

## Table of contents

- [Prerequisites](#prerequisites)
- [Environment setup](#environment-setup)
- [Build & test](#build--test)
- [Deploy to Hedera testnet](#deploy-to-hedera-testnet)
- [Create HTS token](#create-hts-token)
- [Create pool and add liquidity](#create-pool-and-add-liquidity)
- [Add or remove liquidity](#add-or-remove-liquidity)
- [Verify contracts](#verify-contracts)
- [Script reference](#script-reference)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Hedera testnet account with HBAR (e.g. [Hedera Portal](https://portal.hedera.com/))
- For HTS and modify-liquidity scripts: **ECDSA (EVM)** account key matching your `PRIVATE_KEY`

---

## Environment setup

All `./scripts/*.sh` scripts load variables from a **`.env`** file in the project root (if present). Create `.env` and add your values so you don’t need to `export` every time. **Do not commit `.env`** (it is in `.gitignore`).

**Example `.env`:**

```bash
# Required for deploy and scripts
PRIVATE_KEY=0x...

# After deploying (see below)
POOL_MANAGER_ADDRESS=0x...
ROUTER_ADDRESS=0x...

# Token addresses (HTS long-zero format, e.g. from Create HTS token + second token)
CURRENCY0_ADDRESS=0x00000000000000000000000000000000007b4Ff0
CURRENCY1_ADDRESS=0x00000000000000000000000000000000007b4ff9

# Amounts to send to router when adding liquidity (token base units)
AMOUNT0=1000000
AMOUNT1=1000000
```

Optional: `RPC_URL` (default `https://testnet.hashio.io/api`), `HTS_VALUE`, `FEE`, `TICK_SPACING`, `LIQUIDITY_DELTA`, etc. See each section below.

---

## Build & test

**Build:**

```bash
forge build
```

**Run all tests:**

```bash
forge test
```

**Run tests with gas report:**

```bash
forge test --gas-report
```

**Run only PoolManager tests:**

```bash
forge test --match-path test/PoolManager/
```

**Run HTS / modify-liquidity tests** (use hedera-forking emulation at `0x167`; requires FFI):

```bash
forge test --match-path test/PoolManager/modifyLiquidity.t.sol --ffi
```

**Format code:**

```bash
forge fmt
```

**Gas snapshot (baseline):**

```bash
forge snapshot
```

---

## Deploy to Hedera testnet

Deploy **in order**: PoolManager first, then ModifyLiquidityRouter. Scripts load `.env` automatically.

### Step 1 – Deploy PoolManager

```bash
./scripts/deploy-pool-manager.sh
```

Or with Forge:

```bash
forge script script/DeployPoolManagerOnly.s.sol:DeployPoolManagerOnlyScript \
  --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY
```

**Save the logged `PoolManager` address** and set `POOL_MANAGER_ADDRESS` in `.env`.

### Step 2 – Deploy ModifyLiquidityRouter

Set the PoolManager address from Step 1, then run:

```bash
# In .env: POOL_MANAGER_ADDRESS=0x...
./scripts/deploy-router.sh
```

Or with Forge:

```bash
export POOL_MANAGER_ADDRESS=0x...   # from Step 1
forge script script/DeployModifyLiquidityRouterOnly.s.sol:DeployModifyLiquidityRouterOnlyScript \
  --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY
```

**Save the logged `ModifyLiquidityRouter` address** and set `ROUTER_ADDRESS` in `.env`. Use these addresses in your frontend (e.g. `VITE_POOL_MANAGER_ADDRESS`, `VITE_ROUTER_ADDRESS`).

---

## Create HTS token

Creates a fungible HTS token on Hedera testnet (name "HTS Token Example Created with Foundry", symbol `FDRY`, 1M initial supply, 4 decimals). Treasury is the signer. Requires HBAR for the creation fee.

```bash
./scripts/deploy-token.sh
```

Or with Forge (use `--ffi` and `--skip-simulation`):

```bash
forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript \
  --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
```

**Optional env:** `HTS_VALUE` (default 25 ether), `HTS_CREATE_GAS_LIMIT` (default 2M; avoids `INSUFFICIENT_TX_FEE`).

**Getting the real token address:** The script prints an address from local HTS emulation (often `0x...0408`). The **actual** token address is assigned by Hedera—get it from the broadcast transaction on [HashScan Testnet](https://hashscan.io/testnet) (open the tx → contract call to `0x167` → result/logs). Use that address as `CURRENCY0_ADDRESS` or `CURRENCY1_ADDRESS` for pools.

---

## Create pool and add liquidity

Creates a **new pool** at 1:1 price and adds liquidity in one run. You need two token addresses (e.g. two HTS tokens from the create-token script).

**Required in `.env`:** `PRIVATE_KEY`, `POOL_MANAGER_ADDRESS`, `ROUTER_ADDRESS`, `CURRENCY0_ADDRESS`, `CURRENCY1_ADDRESS`, and **both** `AMOUNT0` and `AMOUNT1` (in token base units; caller must hold the tokens).

```bash
# Example: 1e6 base units each (with 4 decimals = 100 tokens each)
export AMOUNT0=1000000
export AMOUNT1=1000000
./scripts/create-pool-and-add-liquidity.sh
```

Or with Forge (for HTS tokens you’d also need `htsSetup` and `--ffi` in the script; the shell script doesn’t use HTS by default for this path—prefer the modify-liquidity script for HTS):

```bash
forge script script/CreatePoolAndAddLiquidityTestnet.s.sol:CreatePoolAndAddLiquidityTestnetScript \
  --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY
```

**Optional env:** `FEE=3000`, `TICK_SPACING=60`, `TICK_LOWER=-120`, `TICK_UPPER=120`, `LIQUIDITY_DELTA=1e18`.

---

## Add or remove liquidity

Use this to **add or remove liquidity** on a pool. The script will **initialize the pool at 1:1** if it doesn’t exist yet, then transfer tokens to the router (if `AMOUNT0`/`AMOUNT1` are set) and call `modifyLiquidity`. Works with HTS tokens (uses `htsSetup` and `--ffi --skip-simulation`).

**Required in `.env`:** `PRIVATE_KEY`, `POOL_MANAGER_ADDRESS`, `ROUTER_ADDRESS`, `CURRENCY0_ADDRESS`, `CURRENCY1_ADDRESS`.

**Recommended:** Set `AMOUNT0` and `AMOUNT1` (in token base units) so the router can settle. Default `LIQUIDITY_DELTA` is **1e8** (works with e.g. 1e6 each). For larger liquidity (e.g. 1e18) you need ~6e15 of each token.

```bash
# Default liquidity delta 1e8; 1e6 amount each is enough
./scripts/run-modify-liquidity.sh
```

Or with Forge:

```bash
forge script script/ModifyLiquidityTestnet.s.sol:ModifyLiquidityTestnetScript \
  --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
```

**Optional env:** `FEE=3000`, `TICK_SPACING=60`, `TICK_LOWER=-120`, `TICK_UPPER=120`, `LIQUIDITY_DELTA` (default `1e8`; use negative to remove), `AMOUNT0`, `AMOUNT1`, `SALT`. Currencies are sorted by address inside the script, so order of `CURRENCY0_ADDRESS` / `CURRENCY1_ADDRESS` does not matter.

---

## Verify contracts

Hedera uses [verify.hashscan.io](https://verify.hashscan.io/) (Sourcify). The verify script prints artifact paths and links; it does not call `forge verify-contract` (incompatible with Hedera’s format).

```bash
export POOL_MANAGER_ADDRESS=0x...
export ROUTER_ADDRESS=0x...
./scripts/verify-contracts.sh
```

Then upload the suggested metadata and source files at the provided links. See [How to verify a smart contract on HashScan](https://docs.hedera.com/hedera/tutorials/smart-contracts/how-to-verify-a-smart-contract-on-hashscan).

---

## Script reference

| Script | Purpose |
|--------|--------|
| `./scripts/deploy-pool-manager.sh` | Deploy PoolManager |
| `./scripts/deploy-router.sh` | Deploy ModifyLiquidityRouter (needs `POOL_MANAGER_ADDRESS`) |
| `./scripts/deploy-token.sh` | Create HTS fungible token |
| `./scripts/create-pool-and-add-liquidity.sh` | Initialize pool at 1:1 and add liquidity |
| `./scripts/run-modify-liquidity.sh` | Initialize (if needed) + add/remove liquidity |
| `./scripts/verify-contracts.sh` | Print verification paths for HashScan |

All deploy/run scripts load `.env` from the project root. Broadcast logs and `deployedaddress.txt` are in `.gitignore`.

---

## Troubleshooting

### `INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE`

Hedera requires the **full** signer public key (33 bytes for ECDSA) in the signature map for HTS precompile calls.

- Use an **ECDSA (EVM)** Hedera account whose key matches `PRIVATE_KEY` (e.g. [Hedera Portal](https://portal.hedera.com/) with EVM/ECDSA).
- Try another RPC if the relay doesn’t send the full key.
- Fallback: create the token via [@hashgraph/sdk](https://github.com/hashgraph/hedera-sdk-js) `TokenCreateTransaction` and use the returned token ID/address.

### `INSUFFICIENT_TX_FEE`

The relay often can’t estimate gas for HTS. The create-token script sets an explicit gas limit (`HTS_CREATE_GAS_LIMIT`, default 2M). If it still fails, increase `HTS_VALUE` (e.g. 30 ether) or `HTS_CREATE_GAS_LIMIT` (e.g. 4e6).

### `InvalidFEOpcode` when running scripts

Hedera RPC returns `0xfe` for `eth_getCode(0x167)` (HTS precompile). Scripts that call HTS (create token, modify liquidity with HTS tokens) use [hedera-forking](https://github.com/hashgraph/hedera-forking) and call `htsSetup()` so the emulation is at `0x167`; they must be run with **`--ffi`** and, for broadcast, **`--skip-simulation`**. The shell scripts already pass these where needed. See the [hedera-forking README](https://github.com/hashgraph/hedera-forking) for details.

### `_transfer: insufficient balance` in modify liquidity

The router must hold enough token base units for the requested `LIQUIDITY_DELTA`. Default is `1e8` (works with e.g. `AMOUNT0=AMOUNT1=1000000`). If you set `LIQUIDITY_DELTA=1e18`, you need roughly **6e15** base units of each token (set `AMOUNT0` and `AMOUNT1` accordingly).

### `PoolNotInitialized`

The modify-liquidity script now **initializes the pool at 1:1** if it isn’t initialized yet. Ensure you’re using the latest script and that `POOL_MANAGER_ADDRESS` is set.

---

## Links

- [**Hedera forking**](https://github.com/hashgraph/hedera-forking) — HTS emulation for Foundry/Hardhat; read this to learn fork testing and HTS at `0x167`
- [Foundry Book](https://book.getfoundry.sh/)
- [Hedera Testnet](https://hashscan.io/testnet)
- [Hedera Smart Contracts](https://docs.hedera.com/hedera/core-concepts/smart-contracts)
- [Verify on HashScan](https://verify.hashscan.io/)
