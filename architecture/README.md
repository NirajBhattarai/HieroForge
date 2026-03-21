# HieroForge — system architecture

Visual overview of how the **UI**, **off-chain services**, and **on-chain contracts** fit together. HieroForge is a Uniswap V4–style concentrated liquidity AMM on **Hedera** (chain id **296** testnet), with **HTS** token support.

**PoolManager–only deep dive:** **[pool-manager.md](./pool-manager.md)** — singleton state, lock/unlock, deltas, `sync`/`settle`/`take`, hooks.

---

## 1. System context

Who talks to whom at the highest level.

```mermaid
flowchart LR
  subgraph Users
    U[Trader / LP]
  end

  subgraph Client
    UI[HieroForge UI\nNext.js + React]
  end

  subgraph Wallet
    HP[HashPack\nHashConnect]
  end

  subgraph Hedera
    EVM[Hedera EVM\nJSON-RPC]
    MN[Mirror Node REST]
  end

  subgraph OffChain["Off-chain (optional)"]
    DDB[(DynamoDB\npools & tokens)]
  end

  U --> UI
  UI --> HP
  HP --> EVM
  UI --> MN
  UI --> DDB
```

---

## 2. Containers and responsibilities

```mermaid
flowchart TB
  subgraph ui["ui/ — Next.js app"]
    APP[App + components\nSwap, positions, explore]
    API[Route handlers\n/api/pools, /api/tokens]
    LIB[lib/\nhederaContract, addLiquidity, swap, quote]
    APP --> API
    APP --> LIB
  end

  subgraph core_pkg["hieroforge-core/ — Solidity"]
    PM[PoolManager\nsingleton pools + math]
  end

  subgraph periph_pkg["hieroforge-periphery/ — Solidity"]
    UR[UniversalRouter]
    POS[PositionManager\nERC-721 positions]
    Q[V4Quoter]
    HFV4[HieroForgeV4Position\nHTS NFT collection]
  end

  API --> DDB[(DynamoDB)]
  LIB --> HP[HashPack signer]
  HP --> EVM[Hedera EVM]
  EVM --> PM
  UR --> PM
  POS --> PM
  Q --> PM
  HFV4 -.->|reads pool context| PM
```

---

## 3. On-chain dependency graph

All pool state and swap math live in **PoolManager**. Periphery contracts are thin orchestration layers.

```mermaid
flowchart BT
  PM[PoolManager\nhieroforge-core]

  UR[UniversalRouter]
  VR[V4Router]
  POS[PositionManager]
  Q[V4Quoter]
  HF[HieroForgeV4Position]

  UR --> VR
  UR --> POS
  VR --> PM
  POS --> PM
  Q --> PM
  HF -->|operator / pool awareness| PM

  style PM fill:#1a3d2e,color:#e8f5e9
```

| Contract | Role |
|----------|------|
| **PoolManager** | Single contract holding every pool; `swap`, `modifyLiquidity`, deltas / unlock pattern. |
| **UniversalRouter** | User entry: command bytes (`V4_SWAP`, `V4_POSITION_CALL`, …). |
| **V4Router** | Encodes swap steps; pays tokens into the pool manager flow. |
| **PositionManager** | NFT positions; `multicall`, `initializePool`, `modifyLiquidities` (mint / increase / decrease / burn). |
| **V4Quoter** | Static calls that revert with quote results (no state change). |
| **HieroForgeV4Position** | Optional HTS-backed NFT collection (no royalties); separate from standard `PositionManager` ERC-721. |

---

## 4. Swap path (simplified)

```mermaid
sequenceDiagram
  participant User
  participant UI
  participant Wallet as HashPack
  participant Quoter as V4Quoter
  participant Router as UniversalRouter
  participant Core as PoolManager

  User->>UI: Confirm swap
  UI->>Quoter: quote (static / eth_call)
  Quoter-->>UI: expected out + gas hint
  UI->>Wallet: sign ContractExecuteTransaction
  Wallet->>Router: execute(commands, inputs)
  Router->>Core: unlock + swap + settle
  Core-->>Router: deltas settled
  Router-->>Wallet: success
```

---

## 5. Liquidity path (PositionManager NFT)

```mermaid
sequenceDiagram
  participant User
  participant UI
  participant Wallet as HashPack
  participant PM as PositionManager
  participant Core as PoolManager

  Note over User,Core: New position — mint NFT + first deposit
  User->>UI: Create position / add amounts
  UI->>Wallet: optional ERC20 transfer to PM then multicall
  Wallet->>PM: multicall(initializePool?, modifyLiquidities)
  PM->>Core: modifyLiquidity + settle

  Note over User,Core: Existing position — same range, more liquidity
  User->>UI: Add to position
  UI->>Wallet: transfer / approve + modifyLiquidities
  PM->>Core: increase liquidity for tokenId
```

---

## 6. UI module map (source layout)

```mermaid
flowchart LR
  subgraph pages["app/"]
    P[page.tsx]
    R[api/*]
  end

  subgraph features["components/"]
    SC[SwapCard]
    NP[NewPosition]
    PP[PoolPositions]
    PD[PositionDetail]
    M[Add/Remove/Burn modals]
  end

  subgraph integration["lib + hooks"]
    HC[hederaContract.ts]
    AL[addLiquidity.ts]
    SW[swap.ts]
    QU[quote.ts]
    HK[useTokens / usePositions / useTokenBalance]
  end

  P --> features
  features --> integration
  R --> DDB[(DynamoDB)]
  integration --> HC
```

---

## 7. Repository layout (monorepo)

```
HieroForge/
├── architecture/          # System diagrams (this README) + PoolManager deep dive (pool-manager.md)
├── hieroforge-core/       # PoolManager, types, libraries, Foundry tests & deploy scripts
├── hieroforge-periphery/  # Router, PositionManager, Quoter, HieroForgeV4Position, scripts/
├── ui/                    # Next.js frontend + API routes
└── .gitmodules            # forge-std, solmate, hedera-forking, etc.
```

---

## Viewing these diagrams

- **GitHub**: Mermaid renders automatically in `README.md` on github.com.
- **VS Code**: Mermaid preview extension, or [mermaid.live](https://mermaid.live).
- **Exports**: Mermaid CLI or mermaid.live → SVG / PNG for slides.
