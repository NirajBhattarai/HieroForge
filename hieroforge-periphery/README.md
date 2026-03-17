# HieroForge Periphery — User-Facing Contracts

Periphery contracts for **HieroForge**: they help users **swap tokens** and **manage liquidity positions** by calling the core AMM (**hieroforge-core**).

## Role

- **hieroforge-core** holds the `PoolManager`, pool state, and swap logic. It is the single source of truth for liquidity and pricing.
- **hieroforge-periphery** provides user-facing contracts (e.g. **UniversalRouter** / **V4Router** for swaps, **PositionManager** for liquidity) that:
  - Encode swap parameters and call the core `PoolManager`
  - Handle the unlock callback and settle/take flows so users can swap tokens against pools created by the core

Position NFTs use standard `approve` / `setApprovalForAll` only. EIP-712 has been removed (not supported on Hedera).

**HieroForgeV4Position** is an HTS NFT collection for V4 positions: create collection + mint only, **no royalties** (0% on secondary). Deploy via `DeployHieroForgeV4Position.s.sol` or `./scripts/deploy-hieroforge-v4-position.sh`; requires Hedera ECDSA key and `--ffi --skip-simulation` for HTS precompile.

Deploy **hieroforge-core** first (PoolManager and any pools). Then deploy periphery contracts that point at the core's PoolManager address. The UI or scripts should use periphery to perform token swaps.

## Folder Structure

```
hieroforge-periphery/
├── src/                                    # Solidity source contracts
│   ├── UniversalRouter.sol                 #   User-facing entry — command dispatcher
│   │                                       #     V4_SWAP (0x10) → swap via V4Router
│   │                                       #     V4_POSITION_CALL (0x11) → PositionManager
│   │                                       #     SWEEP (0x12) → sweep leftover tokens
│   ├── V4Router.sol                        #   Abstract swap router — single & multi-hop swaps
│   │                                       #     _swapExactInputSingle, _swapExactInput (multi-hop)
│   │                                       #     _swapExactOutputSingle, _swapExactOutput (multi-hop)
│   │                                       #     _pay() — ERC-20 transferFrom to PoolManager
│   ├── PositionManager.sol                 #   NFT-based liquidity positions (ERC-721)
│   │                                       #     MINT_POSITION, INCREASE_LIQUIDITY,
│   │                                       #     DECREASE_LIQUIDITY, BURN_POSITION
│   │                                       #     Inherits Multicall_v4 for atomic batching
│   ├── HieroForgeV4Position.sol            #   HTS NFT collection for V4 positions (no royalties)
│   │                                       #     createCollection(), mintNFT(to); owner-only
│   ├── V4Quoter.sol                        #   Off-chain quoter (revert-and-parse pattern)
│   │                                       #     quoteExactInputSingle, quoteExactOutputSingle
│   │                                       #     quoteExactInput, quoteExactOutput (multi-hop)
│   ├── Quoter.sol                          #   Simpler quoter (revert-only, no return)
│   ├── base/                               #   Abstract base contracts
│   │   ├── BaseActionsRouter.sol           #     Action dispatch: unlock → loop _handleAction()
│   │   ├── DeltaResolver.sol               #     Settlement helper (settle, take, mapAmounts)
│   │   ├── SafeCallback.sol                #     Ensures only PoolManager calls unlockCallback
│   │   ├── ImmutableState.sol              #     Stores immutable poolManager reference
│   │   ├── ERC721Permit_v4.sol             #     Position NFT (Solmate ERC-721, no EIP-712)
│   │   ├── ERC721Positions.sol             #     Pure ERC-721 implementation (fallback)
│   │   ├── PoolInitializer_v4.sol          #     Pool init helper (no-op if already initialized)
│   │   ├── Multicall_v4.sol                #     Batch delegatecalls for atomic multi-step ops
│   │   ├── BaseQuoter.sol                  #     Base for simple Quoter
│   │   └── BaseV4Quoter.sol                #     Base for V4Quoter (SafeCallback-based)
│   ├── libraries/                          #   Utility libraries
│   │   ├── Actions.sol                     #     Action type constants (0x00–0x18)
│   │   ├── Commands.sol                    #     UniversalRouter command types + flags
│   │   ├── CalldataDecoder.sol             #     Gas-efficient assembly calldata parsing
│   │   ├── PathKey.sol                     #     Multi-hop path segment struct
│   │   ├── ActionConstants.sol             #     Magic values (OPEN_DELTA, MSG_SENDER, etc.)
│   │   ├── QuoterRevert.sol               #     Quote revert encoding/parsing
│   │   └── Locker.sol                      #     Transient storage msg.sender tracking
│   ├── interfaces/                         #   Contract interfaces
│   │   ├── IV4Router.sol                   #     Swap param structs + slippage errors
│   │   ├── IUniversalRouter.sol            #     execute(commands, inputs, deadline)
│   │   ├── IPositionManager.sol            #     modifyLiquidities(unlockData, deadline)
│   │   ├── IV4Quoter.sol                   #     Quote functions returning (amount, gasEstimate)
│   │   ├── IQuoter.sol                     #     Simpler quote interface
│   │   ├── IERC721Permit_v4.sol            #     NFT authorization error
│   │   ├── IImmutableState.sol             #     poolManager() getter
│   │   ├── IMsgSender.sol                  #     msgSender() view
│   │   ├── IMulticall_v4.sol               #     multicall(bytes[])
│   │   └── IPoolInitializer_v4.sol         #     initializePool(key, sqrtPriceX96)
│   └── types/
│       └── PositionInfo.sol                #   Bit-packed position: poolId + ticks + subscriber
├── test/                                   # Foundry test suite
│   ├── HieroForgeV4Position.t.sol          #   HieroForgeV4Position: deploy, createCollection, mint, onlyOwner (--ffi)
│   ├── Quoter.t.sol                        #   V4Quoter: single-hop quotes, edge cases
│   ├── V4RouterSwapTest.sol                #   UniversalRouter: exact-in/out single-hop swaps
│   ├── V4RouterMultiHopTest.sol            #   Multi-hop swaps (A→B→C), settlement actions
│   ├── position-managers/
│   │   ├── PositionManager.t.sol           #   Mint, increase, decrease, burn positions
│   │   └── PositionManagerFromDeltas.t.sol #   FROM_DELTAS variants + explicit settlement
│   ├── utils/
│   │   ├── QuoterTestDeployers.sol         #   HTS-based test setup (PoolManager + tokens + pool)
│   │   ├── QuoterTestDeployersMock.sol     #   MockERC20-based setup (no HTS node needed)
│   │   └── MockERC20.sol                   #   Minimal ERC-20 mock
│   └── mocks/
│       └── MockHTS.sol                     #   Mock HTS precompile (etched at 0x167)
├── script/                                 # Foundry deploy/setup scripts
│   ├── DeployPositionManager.s.sol         #   Deploy PositionManager(poolManager)
│   ├── DeployHieroForgeV4Position.s.sol    #   Deploy HieroForgeV4Position(operatorAccount) + createCollection (--ffi --skip-simulation)
│   ├── DeployUniversalRouter.s.sol         #   Deploy UniversalRouter(poolManager, positionManager)
│   ├── DeployQuoter.s.sol                  #   Deploy V4Quoter(poolManager)
│   ├── AddLiquidityPositionManager.s.sol   #   Multicall: initializePool + modifyLiquidities
│   ├── TransferToPositionManager.s.sol     #   Transfer tokens to PositionManager
│   ├── TransferHts.s.sol                   #   Generic HTS token transfer
│   ├── CreateTwoHtsTokens.s.sol            #   Create 2 HTS fungible tokens
│   ├── CreateHtsNftToken.s.sol             #   Create HTS NFT for PositionManager
│   ├── DeployMockTokens.s.sol              #   Deploy 2 MockERC20 (local/test)
│   └── DeployAndAddLiquidityLocal.s.sol    #   One-shot local: deploy all + mint position
├── scripts/                                # Shell script wrappers
│   ├── deploy.sh                           #   Full-stack deploy (pool-manager, tokens, PM, etc.)
│   ├── deploy-hieroforge-v4-position.sh     #   Deploy HieroForgeV4Position (HTS NFT, no royalties) to testnet (--ffi --skip-simulation)
│   ├── modify.sh                           #   Multicall: initializePool + modifyLiquidities
│   ├── transfer-to-position-manager.sh     #   Transfer tokens to PositionManager
│   ├── transfer-hts.sh                     #   Transfer HTS tokens to any recipient
│   ├── associate-hts.sh                    #   Associate signer with HTS token
│   ├── create-pool-cast.sh                 #   Create pool + liquidity via cast send
│   └── verify-contracts.sh                 #   Verify contracts on HashScan
├── foundry.toml                            # Build config (Cancun EVM, via_ir, remappings)
└── lib/                                    # Git submodules
    ├── forge-std/                          #   Foundry standard library
    ├── hedera-smart-contracts/             #   HTS precompile interfaces
    ├── hedera-forking/                     #   HTS emulation for local testing
    ├── solmate/                            #   Solmate (ERC-721 base)
    └── permit2/                            #   Uniswap Permit2 (not used on Hedera)
```

## Key Architecture

### Contract Interaction Flow

```
User (UI / Script)
  │
  ├── UniversalRouter.execute(commands, inputs, deadline)
  │     ├── V4_SWAP (0x10) → V4Router._executeV4Swap()
  │     │     └── poolManager.unlock(actionsData)
  │     │           └── unlockCallback() → loop _handleAction():
  │     │                 SWAP_EXACT_IN_SINGLE → poolManager.swap()
  │     │                 SETTLE_ALL → transferFrom(user → PM) + settle()
  │     │                 TAKE_ALL → poolManager.take() → user
  │     │
  │     ├── V4_POSITION_CALL (0x11) → positionManager.modifyLiquidities()
  │     │     └── poolManager.unlock() → MINT/INCREASE/DECREASE/BURN
  │     │
  │     └── SWEEP (0x12) → sweep leftover tokens to recipient
  │
  ├── PositionManager.modifyLiquidities(unlockData, deadline)
  │     └── (same unlock → action dispatch pattern)
  │
  └── V4Quoter.quoteExactInputSingle(params)   [off-chain / eth_call]
        └── try poolManager.unlock() → swap → revert QuoteSwap(amount)
        └── catch → parseQuoteAmount() → return (amount, gasEstimate)
```

### Key Patterns

- **Actions Encoding**: `abi.encode(bytes actions, bytes[] params)` — each byte in `actions` is an action ID, `params[i]` is ABI-encoded args for that action
- **FROM_DELTAS**: `MINT_POSITION_FROM_DELTAS` skips auto-settlement; caller must follow with `SETTLE_PAIR`/`CLOSE_CURRENCY`
- **Position NFTs**: ERC-721 with incrementing tokenId. Position data bit-packed in `PositionInfo`
- **Quoter Revert Pattern**: V4Quoter simulates swaps inside unlock then reverts with `QuoteSwap(amount)`; outer function catches and parses

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
| HieroForgeV4Position tests (HTS NFT) | `forge test --match-contract HieroForgeV4PositionTest --ffi` |
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
| `./scripts/deploy-hieroforge-v4-position.sh` | Deploy **HieroForgeV4Position** (HTS NFT collection for V4 positions, no royalties). Requires `PRIVATE_KEY` or `HEDERA_PRIVATE_KEY` in `.env`; optional `OPERATOR_ACCOUNT`, `HTS_VALUE`, `HTS_CREATE_GAS_LIMIT`. Use `--ffi --skip-simulation`. |
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
