import { useState, useCallback, useEffect, useRef } from 'react'
import { createWalletClient, createPublicClient, custom, http, parseUnits, formatUnits } from 'viem'
import './App.css'
import { useHashPack } from './context/HashPackContext'
import { PoolManagerAbi, SQRT_PRICE_PRESETS } from './abis/PoolManager'
import { quoteExactInputSingle, NotEnoughLiquidityError } from './lib/quote'
import { getFriendlyErrorMessage } from './lib/errors'
import { ErrorMessage } from './components/ErrorMessage'
import {
  TAB,
  HEDERA_TESTNET,
  DEFAULT_TOKENS,
  getTokenAddress,
  getTokenDecimals,
  getPoolManagerAddress,
  getQuoterAddress,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  type TokenOption,
} from './constants'

interface PoolInfo {
  id: string
  pair: string
  tickSpacing: number
  fee: string
}

interface CreatePoolTx {
  hash: string
}

function App() {
  const [tab, setTab] = useState<string>(TAB.SWAP)
  const {
    accountId,
    formattedAccountId,
    isConnected,
    isInitialized,
    isConnecting,
    error,
    connect,
    disconnect,
  } = useHashPack()

  // Swap state
  const [amountIn, setAmountIn] = useState('')
  const [amountOut, setAmountOut] = useState('')
  const [quoteError, setQuoteError] = useState<string | null>(null)
  const [quoteLoading, setQuoteLoading] = useState(false)
  const [tokenIn, setTokenIn] = useState<TokenOption>(DEFAULT_TOKENS[0])
  const [tokenOut, setTokenOut] = useState<TokenOption>(DEFAULT_TOKENS[1])

  // Add liquidity state
  const [tickLower, setTickLower] = useState('-60')
  const [tickUpper, setTickUpper] = useState('60')
  const [liquidityAmount, setLiquidityAmount] = useState('')
  const [liquidityError, setLiquidityError] = useState<string | null>(null)
  const [liquidityToken0, setLiquidityToken0] = useState<TokenOption>(DEFAULT_TOKENS[0])
  const [liquidityToken1, setLiquidityToken1] = useState<TokenOption>(DEFAULT_TOKENS[1])

  // Create pool state
  const [token0Address, setToken0Address] = useState('')
  const [token1Address, setToken1Address] = useState('')
  const [fee, setFee] = useState('3000')
  const [tickSpacing, setTickSpacing] = useState('60')
  const [initialPriceKey, setInitialPriceKey] = useState('1')
  const [createPoolTx, setCreatePoolTx] = useState<CreatePoolTx | null>(null)
  const [createPoolError, setCreatePoolError] = useState<string | null>(null)
  const [createPoolPending, setCreatePoolPending] = useState(false)

  const poolManagerAddress = getPoolManagerAddress()
  const quoterAddress = getQuoterAddress()

  // Public client for read-only quote (eth_call)
  const publicClientRef = useRef<ReturnType<typeof createPublicClient> | null>(null)
  if (!publicClientRef.current && typeof window !== 'undefined') {
    publicClientRef.current = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(HEDERA_TESTNET.rpcUrls.default.http[0]),
    })
  }

  // Quote exact input: when amountIn or token pair changes, fetch amountOut from Quoter (live update)
  useEffect(() => {
    if (!quoterAddress || !amountIn || amountIn === '.' || amountIn === '0' || amountIn === '0.') {
      if (amountIn === '' || amountIn === '0' || amountIn === '0.') setAmountOut('')
      setQuoteError(null)
      setQuoteLoading(false)
      return
    }
    const addrIn = getTokenAddress(tokenIn.symbol)
    const addrOut = getTokenAddress(tokenOut.symbol)
    if (!addrIn || !addrOut || addrIn === addrOut) {
      setAmountOut('')
      setQuoteError(null)
      setQuoteLoading(false)
      return
    }

    const currency0 = addrIn < addrOut ? addrIn : addrOut
    const currency1 = addrIn < addrOut ? addrOut : addrIn
    const zeroForOne = addrIn < addrOut
    const poolKey = { currency0, currency1, fee: DEFAULT_FEE, tickSpacing: DEFAULT_TICK_SPACING }
    const decimalsIn = getTokenDecimals(tokenIn.symbol)
    const decimalsOut = getTokenDecimals(tokenOut.symbol)

    let cancelled = false
    setQuoteError(null)
    setQuoteLoading(true)
    const id = setTimeout(async () => {
      try {
        let amountInWei: bigint
        try {
          amountInWei = parseUnits(amountIn, decimalsIn)
        } catch {
          if (!cancelled) setAmountOut('')
          if (!cancelled) setQuoteLoading(false)
          return
        }
        const client = publicClientRef.current
        if (!client) {
          if (!cancelled) setQuoteLoading(false)
          return
        }
        const amountOutWei = await quoteExactInputSingle(
          client,
          quoterAddress as `0x${string}`,
          poolKey,
          zeroForOne,
          amountInWei
        )
        if (!cancelled) {
          setAmountOut(formatUnits(amountOutWei, decimalsOut))
          setQuoteError(null)
        }
      } catch (err) {
        if (!cancelled) {
          setAmountOut('')
          setQuoteError(
            err instanceof NotEnoughLiquidityError ? err.message : getFriendlyErrorMessage(err, 'quote')
          )
        }
      }
      if (!cancelled) setQuoteLoading(false)
    }, 300)
    return () => {
      cancelled = true
      clearTimeout(id)
    }
  }, [amountIn, tokenIn.symbol, tokenOut.symbol, quoterAddress])

  const createPool = useCallback(async () => {
    if (!poolManagerAddress || !token0Address || !token1Address) {
      setCreatePoolError('Set VITE_POOL_MANAGER_ADDRESS and both token addresses.')
      return
    }
    const addr0 = token0Address.trim()
    const addr1 = token1Address.trim()
    if (addr0 === addr1) {
      setCreatePoolError('Token addresses must be different.')
      return
    }
    const currency0 = addr0.toLowerCase() < addr1.toLowerCase() ? addr0 : addr1
    const currency1 = addr0.toLowerCase() < addr1.toLowerCase() ? addr1 : addr0
    const feeNum = parseInt(fee, 10)
    const tickSpacingNum = parseInt(tickSpacing, 10)
    if (isNaN(feeNum) || feeNum < 0 || feeNum > 1_000_000) {
      setCreatePoolError('Fee must be 0–1000000 (e.g. 3000 = 0.3%).')
      return
    }
    if (isNaN(tickSpacingNum) || tickSpacingNum < 1 || tickSpacingNum > 32767) {
      setCreatePoolError('Tick spacing must be 1–32767.')
      return
    }
    const sqrtPriceX96 = BigInt(SQRT_PRICE_PRESETS[initialPriceKey] ?? SQRT_PRICE_PRESETS['1'])
    const poolKey = { currency0, currency1, fee: feeNum, tickSpacing: tickSpacingNum, hooks: '0x0000000000000000000000000000000000000000' as const }

    const provider = typeof window !== 'undefined' && (window as unknown as { ethereum?: unknown }).ethereum
    if (!provider) {
      setCreatePoolError('No EVM wallet found. Install MetaMask or use an EVM-compatible wallet on Hedera Testnet.')
      return
    }

    setCreatePoolError(null)
    setCreatePoolPending(true)
    setCreatePoolTx(null)
    try {
      const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport: custom(provider as import('viem').CustomTransport) })
      const [address] = await walletClient.requestAddresses()
      if (!address) {
        setCreatePoolError('Connect your EVM wallet first.')
        setCreatePoolPending(false)
        return
      }
      const hash = await walletClient.writeContract({
        address: poolManagerAddress as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: 'initialize',
        args: [poolKey, sqrtPriceX96],
        account: address,
      })
      setCreatePoolTx({ hash })
    } catch (err: unknown) {
      setCreatePoolError(getFriendlyErrorMessage(err, 'transaction'))
    } finally {
      setCreatePoolPending(false)
    }
  }, [poolManagerAddress, token0Address, token1Address, fee, tickSpacing, initialPriceKey])

  const flipTokens = () => {
    setTokenIn(tokenOut)
    setTokenOut(tokenIn)
    setAmountIn(amountOut)
    setAmountOut('') // re-quote will fill from Quoter
  }

  const pools: PoolInfo[] = [
    { id: '1', pair: 'HBAR / USDC', tickSpacing: 60, fee: '0.3%' },
    { id: '2', pair: 'FORGE / USDC', tickSpacing: 60, fee: '0.3%' },
  ]

  return (
    <div className="app">
      <header className="header">
        <span className="logo">HieroForge</span>
        <nav className="nav">
          <button
            className={`nav-btn ${tab === TAB.SWAP ? 'active' : ''}`}
            onClick={() => setTab(TAB.SWAP)}
          >
            Swap
          </button>
          <button
            className={`nav-btn ${tab === TAB.POOL ? 'active' : ''}`}
            onClick={() => setTab(TAB.POOL)}
          >
            Pool
          </button>
          <button
            className={`nav-btn ${tab === TAB.LIQUIDITY ? 'active' : ''}`}
            onClick={() => setTab(TAB.LIQUIDITY)}
          >
            Add Liquidity
          </button>
        </nav>
        {error && (
          <ErrorMessage
            message={getFriendlyErrorMessage(error, 'wallet')}
            className="header-error-inline"
          />
        )}
        <button
          className={`connect-btn ${isConnected ? 'connected' : ''}`}
          onClick={() => (isConnected ? disconnect() : connect())}
          disabled={isConnecting || !isInitialized}
        >
          {isConnecting
            ? 'Connecting...'
            : isConnected
              ? (formattedAccountId || accountId || '')
              : 'Connect HashPack'}
        </button>
      </header>

      <main className="main">
        {tab === TAB.SWAP && (
          <div className={`card ${quoteError ? 'card--error' : ''}`}>
            <h2 className="card-title">Swap</h2>
            <div className={`token-row ${quoteError ? 'token-row--error' : ''}`}>
              <div className="token-row-label">You pay</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder="0.0"
                  value={amountIn}
                  onChange={(e) => setAmountIn(e.target.value)}
                />
                <select
                  className="token-select"
                  value={tokenIn.id}
                  onChange={(e) =>
                    setTokenIn(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[0])
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="flip-row">
              <button type="button" className="flip-btn" onClick={flipTokens} aria-label="Flip">
                ↓↑
              </button>
            </div>
            <div className={`token-row ${quoteError ? 'token-row--error' : ''}`}>
              <div className="token-row-label">You receive</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder={quoteLoading ? 'Updating…' : '0.0'}
                  aria-invalid={!!quoteError}
                  aria-describedby={quoteError ? 'quote-error-msg' : undefined}
                  value={amountOut}
                  onChange={(e) => setAmountOut(e.target.value)}
                  readOnly={!!quoterAddress}
                  aria-readonly={!!quoterAddress}
                />
                <select
                  className="token-select"
                  value={tokenOut.id}
                  onChange={(e) =>
                    setTokenOut(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[1])
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            {quoteError && (
              <ErrorMessage id="quote-error-msg" message={quoteError} className="quote-error" />
            )}
            <p className="helper">Concentrated liquidity · Price limit optional</p>
            {quoterAddress ? (
              <p className="helper">Live quote from Quoter (exact input). Edit TOKEN_ADDRESSES in src/constants.ts for your token addresses.</p>
            ) : (
              <p className="helper">Set VITE_QUOTER_ADDRESS in .env and TOKEN_ADDRESSES in src/constants.ts to see quoted output.</p>
            )}
            <button
              type="button"
              className="primary-btn"
              disabled={!amountIn || !amountOut || !isConnected}
            >
              Swap
            </button>
          </div>
        )}

        {tab === TAB.POOL && (
          <div className="card">
            <h2 className="card-title">Pools</h2>
            <ul className="pool-list">
              {pools.map((pool) => (
                <li key={pool.id} className="pool-item">
                  <div>
                    <span className="pool-pair">{pool.pair}</span>
                    <div className="pool-meta">
                      Tick spacing {pool.tickSpacing} · Fee {pool.fee}
                    </div>
                  </div>
                </li>
              ))}
            </ul>

            <h3 className="create-pool-title">Create pool</h3>
            <p className="helper">Token addresses must be sorted (currency0 &lt; currency1). Use an EVM wallet on Hedera Testnet (chain 296).</p>
            {poolManagerAddress ? null : (
              <p className="helper create-pool-warn">Set VITE_POOL_MANAGER_ADDRESS in .env to enable.</p>
            )}
            <div className="form-group">
              <label>Token 0 address (currency0)</label>
              <input
                type="text"
                value={token0Address}
                onChange={(e) => setToken0Address(e.target.value)}
                placeholder="0x..."
              />
            </div>
            <div className="form-group">
              <label>Token 1 address (currency1)</label>
              <input
                type="text"
                value={token1Address}
                onChange={(e) => setToken1Address(e.target.value)}
                placeholder="0x..."
              />
            </div>
            <div className="form-group">
              <label>Fee (hundredths of a bip, e.g. 3000 = 0.3%)</label>
              <input
                type="text"
                value={fee}
                onChange={(e) => setFee(e.target.value)}
                placeholder="3000"
              />
            </div>
            <div className="form-group">
              <label>Tick spacing (e.g. 60)</label>
              <input
                type="text"
                value={tickSpacing}
                onChange={(e) => setTickSpacing(e.target.value)}
                placeholder="60"
              />
            </div>
            <div className="form-group">
              <label>Initial price (token1 per token0)</label>
              <select
                className="token-select"
                value={initialPriceKey}
                onChange={(e) => setInitialPriceKey(e.target.value)}
              >
                {Object.keys(SQRT_PRICE_PRESETS).map((k) => (
                  <option key={k} value={k}>{k}</option>
                ))}
              </select>
            </div>
            {createPoolError && (
              <ErrorMessage
                message={createPoolError}
                className="create-pool-err"
                onDismiss={() => setCreatePoolError(null)}
              />
            )}
            {createPoolTx && (
              <p className="helper create-pool-success">
                Tx: <a href={`https://hashscan.io/testnet/transaction/${createPoolTx.hash}`} target="_blank" rel="noreferrer">{createPoolTx.hash?.slice(0, 10)}…</a>
              </p>
            )}
            <button
              type="button"
              className="primary-btn"
              disabled={!poolManagerAddress || createPoolPending}
              onClick={createPool}
            >
              {createPoolPending ? 'Creating…' : 'Create pool'}
            </button>
          </div>
        )}

        {tab === TAB.LIQUIDITY && (
          <div className="card">
            <h2 className="card-title">Add Liquidity</h2>
            {!isConnected && (
              <p className="helper liquidity-hint">Connect your wallet to add liquidity.</p>
            )}
            <div className="form-group">
              <label>Token pair</label>
              <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
                <select
                  className="token-select"
                  style={{ flex: 1 }}
                  value={liquidityToken0.id}
                  onChange={(e) =>
                    setLiquidityToken0(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[0])
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
                <select
                  className="token-select"
                  style={{ flex: 1 }}
                  value={liquidityToken1.id}
                  onChange={(e) =>
                    setLiquidityToken1(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[1])
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="form-group">
              <label>Tick lower (e.g. -60 for tickSpacing 60)</label>
              <input
                type="text"
                value={tickLower}
                onChange={(e) => setTickLower(e.target.value)}
                placeholder="-60"
              />
            </div>
            <div className="form-group">
              <label>Tick upper (e.g. 60 for tickSpacing 60)</label>
              <input
                type="text"
                value={tickUpper}
                onChange={(e) => setTickUpper(e.target.value)}
                placeholder="60"
              />
            </div>
            <div className="form-group">
              <label>Liquidity amount</label>
              <input
                type="text"
                value={liquidityAmount}
                onChange={(e) => {
                  setLiquidityAmount(e.target.value)
                  setLiquidityError(null)
                }}
                placeholder="0"
              />
            </div>
            <p className="helper">
              Liquidity is provided in the selected tick range. Must be multiple of tick spacing.
            </p>
            {liquidityError && (
              <ErrorMessage
                message={liquidityError}
                className="liquidity-error"
                onDismiss={() => setLiquidityError(null)}
              />
            )}
            <button
              type="button"
              className="primary-btn"
              disabled={!liquidityAmount || !isConnected}
              onClick={() => {
                if (!liquidityAmount || liquidityAmount === '0') setLiquidityError('Enter a liquidity amount.')
                else setLiquidityError(null)
              }}
            >
              Add Liquidity
            </button>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
