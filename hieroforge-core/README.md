# HieroForge Core — AMM Engine

Uniswap v4–style concentrated liquidity AMM (PoolManager + ModifyLiquidityRouter) and HTS token creation for **Hedera Testnet**. Built with [Foundry](https://book.getfoundry.sh/).

## Folder Structure

```
hieroforge-core/
├── src/                              # Solidity source contracts
│   ├── PoolManager.sol               #   Singleton AMM core — all pool state, swap, liquidity
│   ├── constants.sol                 #   MIN/MAX tick bounds, tick spacing limits
│   ├── NoDelegateCall.sol            #   Guard against delegatecall (immutable address check)
│   ├── TokenClassifier.sol           #   Classify token addresses as ERC-20 / HTS / Unknown
│   ├── interfaces/                   #   Contract interfaces
│   │   ├── IPoolManager.sol          #     Full PoolManager interface (init, swap, liquidity, etc.)
│   │   └── IERC20Minimal.sol         #     Minimal ERC-20 (balanceOf, transfer, transferFrom)
│   ├── callback/
│   │   └── IUnlockCallback.sol       #   Callback interface for the lock/unlock pattern
│   ├── libraries/                    #   Math & utility libraries
│   │   ├── Lock.sol                  #     Transient storage lock flag (tstore/tload)
│   │   ├── NonzeroDeltaCount.sol     #     Transient counter for unsettled currency deltas
│   │   ├── TokenTypeDetector.sol     #     HTS precompile (0x167) detection + ERC-20 probing
│   │   ├── TickMath.sol              #     Tick ↔ sqrtPriceX96 conversion (Q64.96 format)
│   │   ├── SqrtPriceMath.sol         #     Price-liquidity math (amounts from price ranges)
│   │   ├── SwapMath.sol              #     Per-tick swap step computation (price, fees, amounts)
│   │   ├── TickBitmap.sol            #     Packed bitmap for initialized tick tracking
│   │   ├── FullMath.sol              #     512-bit safe mulDiv (phantom overflow protection)
│   │   ├── BitMath.sol               #     MSB/LSB via De Bruijn sequences
│   │   ├── FixedPoint96.sol          #     Q64.96 constants (RESOLUTION, Q96)
│   │   ├── LiquidityMath.sol         #     Signed delta + unsigned liquidity addition
│   │   ├── SafeCast.sol              #     Safe downcasting (uint256→uint160, int256→int128, etc.)
│   │   ├── UnsafeMath.sol            #     Unchecked divRoundingUp
│   │   └── CustomRevert.sol          #     Gas-efficient custom error reverting (assembly)
│   └── types/                        #   Data structures
│       ├── PoolState.sol             #     Pool state + swap()/modifyLiquidity() implementations
│       ├── PoolKey.sol               #     Pool identifier (currency0, currency1, fee, tickSpacing, hooks)
│       ├── PoolId.sol                #     bytes32 pool hash (keccak256 of PoolKey)
│       ├── Slot0.sol                 #     Packed bytes32: sqrtPriceX96 + tick + fees
│       ├── Currency.sol              #     Token address wrapper + CurrencyDelta transient storage
│       ├── BalanceDelta.sol          #     Packed int256: amount0 (upper) + amount1 (lower)
│       ├── TickInfo.sol              #     Per-tick: liquidityGross, liquidityNet, feeGrowth
│       ├── PositionState.sol         #     Per-position: liquidity, fee growth snapshots
│       ├── SwapParams.sol            #     Swap input parameters
│       ├── SwapResult.sol            #     Swap output (final price, tick, liquidity)
│       ├── StepComputations.sol      #     Per-step intermediate state during swap loop
│       ├── ModifyLiquidityParams.sol #     External liquidity operation parameters
│       ├── PoolOperation.sol         #     Internal operation struct with resolved fields
│       └── BeforeSwapDelta.sol       #     Hook return type for beforeSwap
├── test/                             # Foundry test suite
│   ├── PoolManager/                  #   Integration tests
│   │   ├── initialize.t.sol         #     Pool initialization (prices, tick spacing, reverts)
│   │   ├── modifyLiquidity.t.sol    #     Add/remove liquidity, tick updates, fee accrual
│   │   ├── swap.t.sol               #     Swap flows (exact input, both directions)
│   │   └── core.t.sol               #     Consolidated core tests (events, hooks)
│   ├── libraries/                    #   Unit tests for library functions
│   │   ├── BitMath.t.sol            #     MSB/LSB edge cases
│   │   ├── Lock.t.sol               #     Transient lock toggle behavior
│   │   ├── NonzeroDeltaCount.t.sol  #     Increment/decrement/underflow
│   │   └── TokenTypeDetector.t.sol  #     ERC-20/HTS classification
│   ├── types/                        #   Unit tests for type libraries
│   │   ├── PoolKey.t.sol            #     Validation (sorted, spacing bounds)
│   │   └── PoolState.t.sol          #     Direct state function tests
│   ├── CreateHtsToken.t.sol          #   HTS token creation via emulation
│   ├── TickBitmap.t.sol              #   TickBitmap search (boundary conditions)
│   ├── TokenClassifier.t.sol         #   TokenClassifier facade tests
│   └── utils/                        #   Test helpers
│       ├── Deployers.sol             #     Shared setup: deploy PoolManager+Router, HTS tokens
│       ├── Router.sol                #     Unlock-callback router for test operations
│       ├── MockERC20.sol             #     Minimal ERC-20 mock with mint
│       └── Constants.sol             #     Pre-computed sqrt prices and fee tiers
├── script/                           # Foundry deploy/setup scripts
│   ├── DeployPoolManager.s.sol       #   Deploy PoolManager + Router together
│   ├── DeployPoolManagerOnly.s.sol   #   Deploy PoolManager only
│   ├── DeployModifyLiquidityRouterOnly.s.sol  # Deploy Router only
│   ├── CreateHtsToken.s.sol          #   Create HTS fungible token via precompile
│   ├── MintHtsToken.s.sol            #   Mint additional HTS supply
│   ├── CreatePoolAndAddLiquidityTestnet.s.sol  # Init pool + add liquidity
│   ├── ModifyLiquidityTestnet.s.sol  #   Add liquidity across multiple tick ranges
├── scripts/                          # Shell script wrappers
│   ├── deploy-pool-manager.sh        #   Deploy PoolManager to testnet
│   ├── deploy-router.sh              #   Deploy Router (needs POOL_MANAGER_ADDRESS)
│   ├── deploy-token.sh               #   Create HTS token on testnet
│   ├── mint-token.sh                 #   Mint more HTS tokens
│   ├── create-pool-and-add-liquidity.sh  # Create pool + add liquidity
│   ├── run-modify-liquidity.sh       #   Add/remove liquidity
│   ├── run-initialize-tests.sh       #   Run initialize tests only
│   ├── verify-contracts.sh           #   Verify on HashScan (Sourcify)
│   └── hashscan-verify-api.sh        #   Direct HashScan API helper
├── foundry.toml                      # Build config (Cancun EVM, via_ir, optimizer, RPC)
├── lib/                              # Git submodules
│   ├── forge-std/                    #   Foundry standard library
│   ├── hedera-smart-contracts/       #   HTS precompile interfaces
│   └── hedera-forking/               #   HTS emulation for local testing
└── README.md                         # This file
```

## Key Architecture

- **Singleton PoolManager** — All pools live in one contract (`mapping(PoolId => PoolState)`). No factory; pools are created via `initialize()`.
- **Lock/Unlock Flash Accounting** — Operations (`swap`, `modifyLiquidity`) require `unlock()` → `unlockCallback()`. Deltas tracked in transient storage (`tstore`/`tload`); tokens move once per currency via `sync`/`settle`/`take`.
- **HTS Token Support** — `TokenTypeDetector` probes `0x167` precompile for HTS tokens. `CurrencyLibrary` handles transfers uniformly for both ERC-20 and HTS. Local tests use `htsSetup()` from hedera-forking.
- **Concentrated Liquidity Math** — Full Uniswap V4 math: `TickMath`, `SqrtPriceMath`, `SwapMath`, `TickBitmap`, `FullMath`. Packed storage (`Slot0` = sqrtPrice+tick+fees in one `bytes32`).

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
