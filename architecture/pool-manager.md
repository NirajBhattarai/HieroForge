# PoolManager architecture (hieroforge-core)

The **PoolManager** is the singleton AMM engine: every pool’s state, swap math, and liquidity updates live in one contract. Periphery contracts (**UniversalRouter**, **PositionManager**, test routers) never hold long-lived pool state—they call into PoolManager under the **lock / unlock** pattern and settle **currency deltas** before the outer `unlock` returns.

For the full HieroForge stack diagram, see **[README.md](./README.md)** in this folder.

---

## 1. What PoolManager stores

```mermaid
flowchart TB
  subgraph PM[PoolManager.sol]
    MAP["mapping PoolId => PoolState\n_pools"]
  end

  subgraph PK[Pool identity]
    KEY[PoolKey\ncurrency0, currency1, fee,\ntickSpacing, hooks]
    PID[PoolId = keccak256 abi.encode PoolKey]
  end

  subgraph PS[PoolState per pool]
    S0[Slot0 — sqrtPriceX96, tick, protocol fee flags]
    TICKS[tickBitmap + tick-level liquidity / fees]
    POS[positionKey => liquidity + fee growth]
  end

  KEY --> PID
  PID --> MAP
  MAP --> PS
```

| Concept | Role |
|--------|------|
| **PoolKey** | Canonical pair + fee tier + tick spacing + optional **hooks** contract. `currency0 < currency1`. |
| **PoolId** | `bytes32` hash of the key; used as the mapping key. |
| **PoolState** | Price (`slot0`), tick graph, positions; implements the heavy **swap** and **modifyLiquidity** logic. |

---

## 2. Public entrypoints on PoolManager

```mermaid
flowchart LR
  subgraph AlwaysCallable["No unlock required"]
    INIT[initialize\nPoolKey + sqrtPriceX96]
    GPS[getPoolState\nview]
    CD[currencyDelta\nview]
  end

  subgraph InsideUnlock["onlyWhenUnlocked"]
    ML[modifyLiquidity]
    SW[swap]
    SYN[sync]
    SET[settle]
    TAKE[take]
  end

  subgraph LockPattern[Lock pattern]
    UNL[unlock\ndata]
  end

  EXT[External caller\nrouter / PositionManager]
  EXT --> UNL
  UNL -->|callback| CB[unlockCallback]
  CB --> ML
  CB --> SW
  CB --> SYN
  CB --> SET
  CB --> TAKE
```

- **`initialize`** — Creates pool state at an initial price; may call **beforeInitialize / afterInitialize** hooks.
- **`modifyLiquidity`** — Adds/removes concentrated liquidity; updates ticks and position state; **before/afterModifyLiquidity** hooks; then **accounts deltas** for `msg.sender`.
- **`swap`** — Executes the swap loop inside `PoolState`; **beforeSwap** (optional fee override) / **afterSwap** hooks; **accounts deltas** for `msg.sender`.
- **`unlock`** — Sets transient **lock**, calls `IUnlockCallback(msg.sender).unlockCallback(data)`, then requires **all currency deltas net to zero** (`NonzeroDeltaCount == 0`) before clearing the lock.

---

## 3. Lock / unlock and flash accounting (sequence)

Swaps and liquidity changes **do not** pull tokens inside `swap` / `modifyLiquidity`. They only **record debts and credits** in **transient storage** per `(currency, target)`. The callback **sync + settle + take** (or ERC-20 transfers into the manager) clears those deltas.

```mermaid
sequenceDiagram
  participant Caller as Router / PositionManager
  participant PM as PoolManager
  participant Pool as PoolState

  Caller->>PM: unlock(data)
  PM->>PM: Lock.unlock()
  PM->>Caller: unlockCallback(data)

  Note over Caller,Pool: Inside callback — arbitrary batch
  Caller->>PM: swap(...) or modifyLiquidity(...)
  PM->>Pool: read/write state
  PM-->>Caller: BalanceDelta
  PM->>PM: _accountDelta per currency for msg.sender

  Caller->>PM: sync(currency) + transfer in + settle()
  Note right of PM: settle measures balance increase → positive delta for payer

  Caller->>PM: take(currency, to, amount) when owed tokens
  Note right of PM: negative delta + ERC20 transfer out

  Caller-->>PM: return from unlockCallback
  PM->>PM: require NonzeroDeltaCount == 0
  PM->>PM: Lock.lock()
```

If any address still has a non-zero **currency delta** when `unlock` finishes, the call reverts with **`CurrencyNotSettled`**.

---

## 4. Deltas: sync → settle / take

```mermaid
flowchart LR
  subgraph Debt["Owe tokens TO the pool"]
    SYNC[sync currency]
    XFER[ERC20 transfer to PoolManager\nor native value]
    SET[settle]
    SYNC --> SET
    XFER --> SET
    SET --> ADP[_accountDelta +\namount paid]
  end

  subgraph Credit["Receive tokens FROM the pool"]
    TAKE[take currency, to, amount]
    TAKE --> ADM[_accountDelta − amount]
    TAKE --> OUT[ERC20 transfer to `to`]
  end
```

- **`sync`** snapshots “reserves before” for the chosen currency (transient).
- **`settle`** compares current balance to that snapshot and credits the payer’s delta by the increase (or uses `msg.value` for native HBAR).
- **`take`** applies a negative delta to the caller and transfers tokens out.

---

## 5. Hook touchpoints (summary)

When `PoolKey.hooks` is non-zero and the address’s **permission bits** match, PoolManager invokes:

| Phase | Hook (conceptual) |
|-------|-------------------|
| Init | `beforeInitialize` → state init → `afterInitialize` |
| Liquidity | `beforeModifyLiquidity` → `modifyLiquidity` core → `afterModifyLiquidity` |
| Swap | `beforeSwap` (optional LP fee override) → `swap` core → `afterSwap` |

Hooks run **inside** the same transaction as the user operation; they cannot skip delta settlement—the **unlock** epilogue still requires a clean slate.

---

## 6. File map (core package)

Relevant Solidity under **`hieroforge-core/src/`**:

| Path | Responsibility |
|------|----------------|
| `PoolManager.sol` | Singleton; `initialize`, `modifyLiquidity`, `swap`, `unlock`, `sync`, `settle`, `take`, `currencyDelta`, `getPoolState` |
| `types/PoolState.sol` | Tick crossing, swap loop, liquidity updates |
| `types/PoolKey.sol` / `PoolId.sol` | Identity and validation |
| `types/Currency.sol` | Transient **per-(currency,target)** deltas |
| `libraries/Lock.sol` / `NonzeroDeltaCount.sol` | Transient lock + unsettled delta counting |
| `libraries/Hooks.sol` | Optional external hook calls |
| `callback/IUnlockCallback.sol` | `unlockCallback(bytes)` |

---

## 7. Callers (outside core)

Typical **msg.sender** into `unlock`:

- **PositionManager** (periphery) — `modifyLiquidities` → actions that call `modifyLiquidity` / settlement.
- **UniversalRouter** / **V4Router** — swap commands batched with pays and settles.
- **Test Router** (`hieroforge-core/test/utils/Router.sol`) — minimal unlock wrapper for Foundry tests.

All of them implement **`IUnlockCallback`** and drive **`sync` / `settle` / `take`** so **`CurrencyNotSettled`** never fires at the end of `unlock`.
