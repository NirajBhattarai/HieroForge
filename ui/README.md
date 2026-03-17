# HieroForge UI — Frontend

Frontend for **HieroForge** (concentrated liquidity AMM on Hedera). Built with **Next.js 15** and React 19.

## Folder Structure

```
ui/
├── src/
│   ├── app/                              # Next.js App Router
│   │   ├── layout.tsx                    #   Root HTML layout + Providers wrapper
│   │   ├── Providers.tsx                 #   Client-side provider (dynamic HashPackProvider)
│   │   ├── page.tsx                      #   Home page (renders SPA App component, no SSR)
│   │   ├── not-found.tsx                 #   404 page
│   │   └── api/                          #   Server-side API routes
│   │       ├── pools/
│   │       │   ├── route.ts              #     GET: list pools (DynamoDB + on-chain validation)
│   │       │   │                         #     POST: save pool (validates on-chain first)
│   │       │   └── [poolId]/route.ts     #     GET: single pool by ID
│   │       └── tokens/
│   │           ├── route.ts              #     GET: list tokens; POST: save token
│   │           └── lookup/route.ts       #     GET: resolve token by address via Mirror Node
│   │
│   ├── components/                       # React components
│   │   ├── SwapCard.tsx                  #   Swap panel — token selection, exact-in/out,
│   │   │                                #     live quoting via V4Quoter, multi-hop routing,
│   │   │                                #     fee tier & slippage config, UniversalRouter execute
│   │   ├── Explore.tsx                   #   Top pools table — search, fee badges, pair icons
│   │   ├── PoolPositions.tsx             #   Your positions list — all/my pools, Mirror Node
│   │   │                                #     balances, "Load by pool ID" manual lookup
│   │   ├── PositionDetail.tsx            #   Single pool detail — balances, add/remove/burn
│   │   ├── NewPosition.tsx               #   2-step flow: select pair+fee+price → set range
│   │   │                                #     + amounts → Create Pool / Create+Add Liquidity
│   │   ├── AddLiquidityModal.tsx         #   Add liquidity to existing pool (FROM_DELTAS mode)
│   │   ├── RemoveLiquidityModal.tsx      #   Slider-based % removal (25/50/75/100%)
│   │   ├── BurnPositionModal.tsx         #   Permanently burn position NFT
│   │   ├── Header.tsx                    #   Top nav: logo, tabs, testnet badge, wallet button
│   │   ├── ErrorMessage.tsx              #   Reusable error/warning banner
│   │   ├── TokenIcon.tsx                 #   Token logo with gradient fallback
│   │   └── ui/                           #   UI primitives
│   │       ├── Badge.tsx                 #     Pill badge (default/accent/success/warning)
│   │       ├── Button.tsx                #     Styled button (primary/secondary/ghost/danger)
│   │       ├── Modal.tsx                 #     Glass-morphism overlay modal
│   │       ├── Skeleton.tsx              #     Loading skeleton placeholder
│   │       └── TokenSelector.tsx         #     Token picker modal with search & auto-lookup
│   │
│   ├── lib/                              # Utility modules
│   │   ├── swap.ts                       #   Swap encoding for UniversalRouter.execute()
│   │   │                                #     encodeSwapExactInSingle, encodeSwapExactOutSingle,
│   │   │                                #     encodeSwapExactIn (multi-hop), buildPath
│   │   ├── addLiquidity.ts              #   Liquidity encoding for PositionManager
│   │   │                                #     encodeUnlockDataMint, Decrease, Burn, Increase
│   │   ├── quote.ts                      #   V4Quoter integration — quoteExactInputSingle,
│   │   │                                #     quoteExactOutputSingle, quoteExactInput (multi-hop)
│   │   │                                #     Handles Hedera relay quirks + revert fallback
│   │   ├── hederaContract.ts            #   Hedera SDK bridge — ABI encode (viem) →
│   │   │                                #     ContractExecuteTransaction → HashConnect signer
│   │   │                                #     + waitForTransactionSuccess (Mirror Node polling)
│   │   ├── priceUtils.ts               #   Math: encodePriceSqrt, tickToPrice, priceToTick,
│   │   │                                #     computeLiquidityFromAmount, PRICE_STRATEGIES
│   │   ├── poolValidation.ts           #   On-chain pool existence check via PoolManager
│   │   ├── dynamo-pools.ts             #   DynamoDB CRUD for pool records
│   │   ├── dynamo-tokens.ts            #   DynamoDB CRUD for token records
│   │   ├── tokenRegistry.ts            #   In-memory global token registry (from DynamoDB)
│   │   └── errors.ts                    #   Error normalization → user-friendly messages
│   │
│   ├── hooks/                            # Custom React hooks
│   │   ├── useTokens.ts                 #   Fetch token list from /api/tokens + populate registry
│   │   ├── useTokenBalance.ts           #   HTS balance via Mirror Node REST API
│   │   └── useTokenLookup.ts            #   Resolve token metadata by address (debounced)
│   │
│   ├── context/                          # React context providers
│   │   └── HashPackContext.tsx           #   HashConnect wallet: init, pairing, session,
│   │                                     #     accountId, connect/disconnect, hashConnectRef
│   │
│   ├── abis/                             # Contract ABIs (TypeScript)
│   │   ├── ERC20.ts                      #   Standard ERC-20 (approve, transfer, etc.)
│   │   ├── PoolManager.ts               #   initialize, getPoolState + price presets
│   │   ├── PositionManager.ts           #   multicall, initializePool, modifyLiquidities
│   │   ├── Quoter.ts                     #   V4Quoter: quote functions + QuoteSwap error
│   │   └── UniversalRouter.ts           #   execute(commands, inputs, deadline) + constants
│   │
│   ├── constants/                        # Configuration
│   │   └── index.ts                      #   Chain config (HEDERA_TESTNET), contract addresses,
│   │                                     #     token defaults, fee tiers, tick spacing
│   │
│   └── styles/
│       └── globals.css                   #   Tailwind v4 + dark theme CSS custom properties
│
├── scripts/                              # Build & setup scripts
│   ├── register-pool.cjs                #   CLI: register pool in DynamoDB (computes poolId)
│   ├── register-token.cjs               #   CLI: register token in DynamoDB
│   ├── seed-dynamo.ts                   #   Seed DynamoDB tables with testnet data
│   └── quote-usdc-forge.ts             #   Test script: quote via V4Quoter
│
├── public/                               # Static assets
│   └── vite.svg                          #   (legacy from Vite scaffolding)
│
├── package.json                          # Dependencies & scripts
├── next.config.ts                        # Next.js config
├── tsconfig.json                         # TypeScript config (@ → src/)
├── postcss.config.mjs                    # PostCSS (Tailwind)
├── eslint.config.js                      # ESLint config
└── README.md                             # This file
```

## Key Architecture

```
Browser (Next.js 15)
  │
  ├── Components ──► lib/swap.ts ──► hederaContract.ts ──► HashConnect → Hedera
  │                  lib/addLiquidity.ts                    (ContractExecuteTransaction)
  │                  lib/quote.ts ──► viem PublicClient ──► Hedera JSON-RPC (Hashio)
  │
  ├── API Routes ──► lib/dynamo-*.ts ──► AWS DynamoDB (pool & token storage)
  │                  lib/poolValidation.ts ──► on-chain validation
  │
  └── Hooks ──► Mirror Node REST API (balances, token metadata, tx confirmation)
```

- **Wallet**: HashConnect v3 + WalletConnect. `HashPackContext` initializes singleton, handles pairing/disconnect, exposes `hashConnectRef` for direct contract execution.
- **Contract writes**: ABI-encoded by viem → raw calldata to `ContractExecuteTransaction` → `freezeWithSigner` → `executeWithSigner` → Mirror Node polling for consensus confirmation.
- **Contract reads**: Quotes use viem `PublicClient` + `eth_call`. Token balances use Mirror Node REST API directly.
- **Storage**: DynamoDB for pools/tokens (server-side API routes). Auto-prunes stale pools. Auto-discovers tokens on paste.
- **Styling**: Tailwind CSS v4 with custom Uniswap-inspired dark theme.

### Prerequisites (Node.js & npm)

You need Node.js 18+ and npm. If you get `command not found: npm`:

- **Using nvm:** Run `source ~/.nvm/nvm.sh` then `nvm install` (or `nvm use` if you already have Node). Then run `npm install` in `ui/`.
- **Using Homebrew:** `brew install node`, then `npm install` in `ui/`.
- **Otherwise:** Install from [nodejs.org](https://nodejs.org/) and open a new terminal.

Then from the `ui` folder:

```bash
npm install
npm run dev
```

- **Contracts / ABIs:** `src/abis/` (Quoter, PositionManager, PoolManager, ERC20).
- **Run dev:** `npm run dev` (Next.js dev server)
- **Build:** `npm run build` then `npm run start`

### Environment

1. Copy `ui/.env.example` to `ui/.env.local`.
2. Set `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` (get from [cloud.walletconnect.com](https://cloud.walletconnect.com/)).
3. Set contract addresses: `NEXT_PUBLIC_POOL_MANAGER_ADDRESS`, `NEXT_PUBLIC_QUOTER_ADDRESS`, `NEXT_PUBLIC_POSITION_MANAGER_ADDRESS`. To use HieroForgeV4Position for liquidity/positions, set `NEXT_PUBLIC_HIEROFORGE_V4_POSITION_ADDRESS` (it then replaces PositionManager).
4. Optionally set `NEXT_PUBLIC_HEDERA_NETWORK` (`testnet` | `mainnet` | `previewnet`).

### Pools from DynamoDB (no hardcoded list)

Pools are stored in **DynamoDB** so you can load any pool by ID and swap without hardcoding.

1. **Create a DynamoDB table** (e.g. in AWS Console or CLI):
   - Table name: `hieroforge-pools` (or set `DYNAMODB_TABLE_POOLS` in env).
   - Partition key: `poolId` (String).
   - No sort key.

2. **Configure AWS** in `ui/.env.local`:
   - `HF_AWS_REGION` (e.g. `us-east-1`)
   - `HF_AWS_ACCESS_KEY_ID` and `HF_AWS_SECRET_ACCESS_KEY` (or use IAM role if deployed to Lambda/ECS).
   - `DYNAMODB_TABLE_POOLS=hieroforge-pools`

3. **In the UI:**
   - **Pool** tab: list is loaded from DynamoDB; use **Load pool by ID** to paste a pool ID (e.g. after creating a pool) and prefill swap/liquidity.
   - When creating a pool or adding liquidity, click **Save pool to list** to store it in DynamoDB for easy loading later.

### HashPack wallet

Install [HashPack](https://www.hashpack.app/) and click **Connect HashPack** in the app.
