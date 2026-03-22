# HieroForge

**HieroForge** is a full-stack concentrated liquidity AMM (Automated Market Maker) built natively for the **Hedera** network. It brings Uniswap V4-style architecture — singleton PoolManager, transient storage delta accounting, tick-based concentrated liquidity, and NFT positions — to Hedera with first-class support for **Hedera Token Service (HTS)** tokens alongside standard ERC-20 tokens.

## Key Features

- **Concentrated Liquidity** — Liquidity providers (LPs) deposit tokens into custom price ranges (tick intervals), maximizing capital efficiency.
- **Singleton PoolManager** — All pools live inside a single `PoolManager` contract. No factory deployment per pool.
- **Flash Accounting (Lock/Unlock)** — Token transfers happen once per currency per operation batch via transient storage deltas, reducing gas costs.
- **HTS-Native** — Full support for Hedera Token Service tokens (detection, creation, transfers) via the `0x167` precompile, while remaining fully compatible with standard ERC-20 tokens.
- **NFT Positions** — Each liquidity position is represented as an ERC-721 NFT managed by `PositionManager`.
- **UniversalRouter** — A single user-facing contract for both swaps (`V4_SWAP`) and liquidity operations (`V4_POSITION_CALL`), with command-based dispatch.
- **Off-Chain Quoter** — `V4Quoter` simulates swaps via the revert-and-parse pattern for accurate price quotes without on-chain state changes.
- **React Frontend** — Next.js 15 app with HashPack wallet integration, DynamoDB-backed pool/token registry, and Hedera Mirror Node for real-time balances.

---

## Architecture

**Diagrams (Mermaid):** see **[architecture/README.md](architecture/README.md)** for context, containers, on-chain dependencies, and sequence flows.

```
┌─────────────────────────────────────────────────────────────────┐
│                        User (Browser)                           │
│  Next.js 15 + React 19 UI                                      │
│  ├── SwapCard (trade tokens)                                    │
│  ├── NewPosition (create pool + add liquidity)                  │
│  ├── PoolPositions (view positions)                             │
│  └── Explore (browse pools)                                     │
└───────────────┬─────────────────────────────────────────────────┘
                │  WalletConnect / HashConnect
                ▼
┌───────────────────────────────┐    ┌────────────────────────────┐
│  HashPack Wallet              │    │  Hedera Mirror Node        │
│  (signs & submits txs)        │    │  (balances, tx status)     │
└───────────────┬───────────────┘    └────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Hedera Testnet (Chain 296)                    │
│                                                                 │
│  ┌─────────────────┐   ┌──────────────────┐                    │
│  │  hieroforge-core│   │hieroforge-periph │                    │
│  │                 │   │                  │                    │
│  │  PoolManager    │◄──│  UniversalRouter │  (swaps)           │
│  │  (all pools,    │◄──│  PositionManager │  (liquidity NFTs)  │
│  │   swap logic,   │◄──│  V4Quoter       │  (price quotes)    │
│  │   liquidity)    │   │  V4Router       │  (swap encoding)   │
│  │                 │   │                  │                    │
│  └─────────────────┘   └──────────────────┘                    │
│                                                                 │
│  HTS Precompile (0x167) — native token creation & management    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
HieroForge/
├── hieroforge-core/          # Core AMM engine (PoolManager, pool state, swap/liquidity math)
│   ├── src/                  #   Solidity source
│   │   ├── PoolManager.sol   #     Singleton — holds all pools, orchestrates operations
│   │   ├── constants.sol     #     Tick bounds, spacing limits
│   │   ├── NoDelegateCall.sol#     Delegatecall guard
│   │   ├── TokenClassifier.sol#    ERC-20 vs HTS token detection
│   │   ├── libraries/        #     Math & utility libs (TickMath, SqrtPriceMath, SwapMath,
│   │   │                     #       TickBitmap, BitMath, FullMath, Lock, SafeCast, etc.)
│   │   ├── types/            #     Data structures (PoolState, PoolKey, PoolId, Slot0,
│   │   │                     #       Currency, BalanceDelta, TickInfo, PositionState, etc.)
│   │   ├── interfaces/       #     IPoolManager, IERC20Minimal
│   │   └── callback/         #     IUnlockCallback
│   ├── test/                 #   Foundry tests (initialize, swap, modifyLiquidity, libraries)
│   ├── script/               #   Deploy scripts (PoolManager, Router, HTS tokens, pools)
│   └── scripts/              #   Shell wrappers for deploy/test
│
├── hieroforge-periphery/     # Periphery contracts (user-facing routing & position mgmt)
│   ├── src/                  #   Solidity source
│   │   ├── UniversalRouter.sol#    Command dispatcher (V4_SWAP, V4_POSITION_CALL, SWEEP)
│   │   ├── V4Router.sol      #     Abstract swap router (single-hop & multi-hop)
│   │   ├── PositionManager.sol#    NFT-based liquidity positions (mint/increase/decrease/burn)
│   │   ├── V4Quoter.sol      #     Off-chain swap quoter (revert-and-parse pattern)
│   │   ├── base/             #     Base contracts (BaseActionsRouter, DeltaResolver,
│   │   │                     #       SafeCallback, ERC721Permit_v4, Multicall_v4, etc.)
│   │   ├── libraries/        #     Actions, Commands, CalldataDecoder, PathKey, Locker
│   │   ├── interfaces/       #     IV4Router, IUniversalRouter, IPositionManager, IV4Quoter
│   │   └── types/            #     PositionInfo (bit-packed NFT position data)
│   ├── test/                 #   Tests (Quoter, V4Router swaps, multi-hop, PositionManager)
│   ├── script/               #   Deploy scripts (PositionManager, Router, Quoter, tokens)
│   └── scripts/              #   Shell wrappers (deploy.sh, modify.sh, transfer, verify)
│
├── ui/                       # Frontend (Next.js 15 + React 19)
│   ├── src/
│   │   ├── app/              #     Next.js App Router (layout, page, API routes)
│   │   │   └── api/          #       /api/pools, /api/tokens, /api/tokens/lookup
│   │   ├── components/       #     SwapCard, Explore, PoolPositions, PositionDetail,
│   │   │                     #       NewPosition, AddLiquidity/Remove/Burn modals, Header
│   │   ├── lib/              #     swap.ts, addLiquidity.ts, quote.ts, hederaContract.ts,
│   │   │                     #       priceUtils.ts, poolValidation.ts, dynamo-*.ts, errors.ts
│   │   ├── hooks/            #     useTokens, useTokenBalance, useTokenLookup
│   │   ├── context/          #     HashPackContext (wallet connection)
│   │   ├── abis/             #     Contract ABIs (PoolManager, PositionManager, Quoter, etc.)
│   │   └── constants/        #     Chain config, token defaults, fee tiers
│   ├── scripts/              #   DynamoDB seed/register scripts
│   └── public/               #   Static assets
│
├── architecture/             # README.md (system), pool-manager.md, hiero-forge-v4-position.md
│
├── .env.example              # Root env template (PRIVATE_KEY, RPC, etc.)
└── .gitmodules               # Git submodules (hedera-smart-contracts, hedera-forking,
                              #   forge-std, solmate, permit2)
```

---

## How It Works

### Core Concepts

#### 1. Singleton PoolManager (hieroforge-core)
All pools exist as entries in a single `PoolManager` contract — a `mapping(PoolId => PoolState)`. Pools are created by calling `initialize(PoolKey, sqrtPriceX96)` where `PoolKey = {currency0, currency1, fee, tickSpacing, hooks}`.

#### 2. Lock/Unlock + Flash Accounting
All state-mutating operations require the unlock pattern:
1. Caller invokes `poolManager.unlock(data)`
2. PoolManager sets a transient storage lock flag and calls `unlockCallback(data)` on `msg.sender`
3. Inside the callback, the caller performs `modifyLiquidity()` / `swap()` — these accumulate **deltas** in transient storage per-address per-currency
4. The caller **settles** negative deltas (`sync` → transfer tokens → `settle`) and **takes** positive deltas (`take`)
5. After the callback returns, PoolManager asserts all deltas are zero, then re-locks

This means tokens only move once per currency per operation batch.

#### 3. Concentrated Liquidity
LPs provide liquidity in discrete tick ranges. The full Uniswap V4 math stack is implemented: `TickMath` (tick ↔ sqrtPrice), `SqrtPriceMath` (price-liquidity relationships), `SwapMath` (per-step swap computation), `TickBitmap` (initialized tick tracking).

#### 4. HTS Token Support
Hedera Token Service tokens are detected via the `0x167` precompile (`isToken()` check). HTS tokens also expose ERC-20-compatible interfaces, so the PoolManager treats them uniformly through `CurrencyLibrary`. Token creation uses `IHederaTokenService.createFungibleToken()` from the hedera-smart-contracts library.

### Swap Flow
```
User (UI)
  → approve(router, amount)
  → UniversalRouter.execute(commands=[V4_SWAP], inputs, deadline)
    → dispatch(V4_SWAP) → self-call executeV4Swap()
      → poolManager.unlock(actionsData)
        → unlockCallback()
          → SWAP_EXACT_IN_SINGLE → poolManager.swap(poolKey, params)
          → SETTLE_ALL → transferFrom(user → poolManager) + settle()
          → TAKE_ALL → poolManager.take(currency, user, amount)
        ← all deltas zero ✓
```

### Liquidity Flow
```
User (UI)
  → transfer tokens to PositionManager
  → PositionManager.multicall([initializePool(...), modifyLiquidities(...)])
    → poolManager.unlock(actionsData)
      → unlockCallback()
        → MINT_POSITION → poolManager.modifyLiquidity(key, params)
        → ERC-721 NFT minted to user
        → SETTLE_PAIR / CLOSE_CURRENCY
      ← all deltas zero ✓
```

### Quote Flow
```
User (UI)
  → V4Quoter.quoteExactInputSingle(params)
    → try poolManager.unlock(quoteData)
      → unlockCallback()
        → poolManager.swap(key, params)
        → revert QuoteSwap(amountOut)
    → catch → parseQuoteAmount(revertData)
    → return (amountOut, gasEstimate)
```

---

## Prerequisites

- **Foundry** — [Install](https://getfoundry.sh/) (`forge`, `cast`, `anvil`)
- **Node.js 18+** and npm — for the UI
- **Hedera testnet account** with HBAR — get from [Hedera Portal](https://portal.hedera.com/faucet)
- **HashPack wallet** — [Install](https://www.hashpack.app/) browser extension
- **WalletConnect project ID** — [Get one](https://cloud.walletconnect.com/)
- **AWS credentials** — for DynamoDB pool/token storage (or run locally with DynamoDB Local)

---

## Quick Start

### 1. Clone & init submodules

```bash
git clone <repo-url>
cd HieroForge
git submodule update --init --recursive
```

### 2. Environment setup

```bash
cp .env.example .env
# Edit .env — set PRIVATE_KEY (Hedera testnet EOA with HBAR)
```

### 3. Build & test smart contracts

**Core (AMM engine):**
```bash
cd hieroforge-core
forge build
forge test          # Local tests with HTS emulation
```

**Periphery (swap router, position manager):**
```bash
cd hieroforge-periphery
forge build
forge test --ffi    # Requires --ffi for HTS emulation
```

### 4. Deploy to Hedera testnet

**Deploy core (PoolManager):**
```bash
cd hieroforge-core
./scripts/deploy-pool-manager.sh
```

**Deploy periphery (PositionManager + UniversalRouter + Quoter):**
```bash
cd hieroforge-periphery
./scripts/deploy.sh all
```

### 5. Run the UI

```bash
cd ui
cp .env.example .env.local
# Edit .env.local — set:
#   NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=...
#   NEXT_PUBLIC_POOL_MANAGER_ADDRESS=0x...
#   NEXT_PUBLIC_QUOTER_ADDRESS=0x...
#   NEXT_PUBLIC_POSITION_MANAGER_ADDRESS=0x...
#   HF_AWS_REGION, HF_AWS_ACCESS_KEY_ID, HF_AWS_SECRET_ACCESS_KEY
#   DYNAMODB_TABLE_POOLS=hieroforge-pools
#   DYNAMODB_TABLE_TOKENS=hieroforge-tokens

npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) and connect HashPack.

---

## Commands Reference

### Smart Contracts

| Action | Command |
|--------|---------|
| Build core | `cd hieroforge-core && forge build` |
| Build periphery | `cd hieroforge-periphery && forge build` |
| Test core | `cd hieroforge-core && forge test` |
| Test periphery | `cd hieroforge-periphery && forge test --ffi` |
| Test swap routing (HTS) | `cd hieroforge-periphery && forge test --match-contract V4RouterSwapTest --ffi` |
| Test multi-hop swaps | `cd hieroforge-periphery && forge test --match-contract V4RouterMultiHopTest --ffi` |
| Test quoter | `cd hieroforge-periphery && forge test --match-contract QuoterTest --ffi` |
| Test PositionManager | `cd hieroforge-periphery && forge test --match-contract PositionManager --ffi` |
| Deploy PoolManager | `cd hieroforge-core && ./scripts/deploy-pool-manager.sh` |
| Create HTS token | `cd hieroforge-core && ./scripts/deploy-token.sh` |
| Deploy full periphery stack | `cd hieroforge-periphery && ./scripts/deploy.sh all` |
| Verify on HashScan | `cd hieroforge-periphery && ./scripts/verify-contracts.sh` |

### Frontend

| Action | Command |
|--------|---------|
| Install deps | `cd ui && npm install` |
| Dev server | `cd ui && npm run dev` |
| Production build | `cd ui && npm run build` |
| Start production | `cd ui && npm run start` |
| Seed DynamoDB | `cd ui && npx tsx scripts/seed-dynamo.ts` |
| Register pool | `cd ui && node scripts/register-pool.cjs <args>` |
| Register token | `cd ui && node scripts/register-token.cjs <args>` |

---

## Deployed Contracts (Hedera Testnet)

**Network:** testnet · **Chain ID:** 296 · **Explorer:** [HashScan](https://hashscan.io/testnet)

These are the addresses wired in [`ui/.env.example`](ui/.env.example) (`NEXT_PUBLIC_*`). Each name links to the contract on HashScan.

| Contract | Address |
|----------|---------|
| PoolManager | [`0x3F3ED4342339DB8216734E6B8Df467e5e533EE98`](https://hashscan.io/testnet/contract/0x3F3ED4342339DB8216734E6B8Df467e5e533EE98) |
| PositionManager | [`0x97DfF8C7C7ec86A0667C65fd9D731516B42d4d86`](https://hashscan.io/testnet/contract/0x97DfF8C7C7ec86A0667C65fd9D731516B42d4d86) |
| UniversalRouter (V4) | [`0x613b73d632C675211F0B669b3d5c0B76D74B94F0`](https://hashscan.io/testnet/contract/0x613b73d632C675211F0B669b3d5c0B76D74B94F0) |
| V4Quoter | [`0x8Bec1cE092C9852BB15670B03C618D34db80a205`](https://hashscan.io/testnet/contract/0x8Bec1cE092C9852BB15670B03C618D34db80a205) |
| HieroForgeV4Position | [`0x03401a54406740040d34ee3d698064f7199a535d`](https://hashscan.io/testnet/contract/0x03401a54406740040d34ee3d698064f7199a535d) |
| TWAP hook | [`0x3752B89d43262fC9B4A4664e18c856dABd636DE2`](https://hashscan.io/testnet/contract/0x3752B89d43262fC9B4A4664e18c856dABd636DE2) |

---

## Documentation

| Document | Description |
|----------|-------------|
| [architecture/README.md](architecture/README.md) | System architecture — context, containers, on-chain deps, swap & liquidity sequences (Mermaid) |
| [architecture/pool-manager.md](architecture/pool-manager.md) | **PoolManager** only — singleton state, lock/unlock, flash deltas, sync/settle/take, hooks |
| [architecture/hiero-forge-v4-position.md](architecture/hiero-forge-v4-position.md) | **HieroForgeV4Position** — HTS NFT positions vs ERC-721 `PositionManager`, deploy, parity table |
| [hieroforge-core/README.md](hieroforge-core/README.md) | Core contracts — build, test, deploy, troubleshooting |
| [hieroforge-periphery/README.md](hieroforge-periphery/README.md) | Periphery contracts — deploy, scripts, HTS compatibility |
| [ui/README.md](ui/README.md) | Frontend — setup, environment, DynamoDB, HashPack |

**External links:** [Foundry Book](https://book.getfoundry.sh/) · [Hedera docs](https://docs.hedera.com/) · [HashPack](https://www.hashpack.app/) · [WalletConnect Cloud](https://cloud.walletconnect.com/)

**HTS fork testing:** [hedera-forking](https://github.com/hashgraph/hedera-forking) emulates the Hedera Token Service at `0x167` for Foundry fork tests (e.g. `forge test --fork-url https://testnet.hashio.io/api`). See that repo for `ffi`, RPC endpoints, and supported HTS methods.

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Smart Contracts | Solidity ^0.8.13, Foundry (Forge/Cast), EVM Cancun (tstore/tload) |
| Blockchain | Hedera Testnet (Chain 296), HTS Precompile (0x167) |
| Frontend | Next.js 15, React 19, TypeScript, Tailwind CSS v4 |
| Wallet | HashConnect 3.0, WalletConnect, HashPack |
| ABI Encoding | viem 2.46.3 |
| Contract Execution | @hashgraph/sdk 2.80 (ContractExecuteTransaction) |
| Storage | AWS DynamoDB (pools + tokens) |
| Balance/Status | Hedera Mirror Node REST API |
| Dependencies | hedera-smart-contracts, hedera-forking, forge-std, solmate, permit2 |

---

## License

Apache-2.0 (see SPDX headers in source files).
