'use client'

import { useState, useCallback, useEffect, useRef } from 'react'
import { createPublicClient, http, parseUnits, formatUnits } from 'viem'
import './App.css'
import { useHashPack } from '@/context/HashPackContext'
import { quoteExactInputSingle, NotEnoughLiquidityError } from '@/lib/quote'
import { getFriendlyErrorMessage } from '@/lib/errors'
import { ErrorMessage } from '@/components/ErrorMessage'
import { TokenIcon } from '@/components/TokenIcon'
import { PoolPositions, type PoolInfo } from '@/components/PoolPositions'
import { NewPosition } from '@/components/NewPosition'
import { Explore } from '@/components/Explore'
import {
  TAB,
  HEDERA_TESTNET,
  DEFAULT_TOKENS,
  getTokenAddress,
  getTokenDecimals,
  getQuoterAddress,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  type TokenOption,
} from '@/constants'
import { useTokens } from '@/hooks/useTokens'

function App() {
  const [tab, setTab] = useState<string>(TAB.TRADE)
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

  // Dynamic tokens from DynamoDB
  const { tokens: dynamicTokens, loading: tokensLoading } = useTokens()
  const tokenOptions: TokenOption[] = dynamicTokens.length > 0
    ? dynamicTokens.map((t) => ({ id: t.address, symbol: t.symbol, address: t.address, decimals: t.decimals, name: t.name }))
    : DEFAULT_TOKENS

  // Helper: resolve address from TokenOption
  const resolveAddress = (tok: TokenOption): string =>
    (tok.address ?? getTokenAddress(tok.symbol)).toLowerCase()
  const resolveDecimals = (tok: TokenOption): number =>
    tok.decimals ?? getTokenDecimals(tok.symbol)

  // Swap state
  const [amountIn, setAmountIn] = useState('')
  const [amountOut, setAmountOut] = useState('')
  const [quoteError, setQuoteError] = useState<string | null>(null)
  const [quoteLoading, setQuoteLoading] = useState(false)
  const [tokenIn, setTokenIn] = useState<TokenOption>(DEFAULT_TOKENS[0]!)
  const [tokenOut, setTokenOut] = useState<TokenOption>(DEFAULT_TOKENS[1]!)

  // Set default tokens once dynamic list loads
  useEffect(() => {
    if (tokenOptions.length >= 2) {
      setTokenIn(tokenOptions[0]!)
      setTokenOut(tokenOptions[1]!)
    }
  }, [tokenOptions.length])

  // New position form opens in a modal (click "New" or select a pool)
  const [showNewPositionModal, setShowNewPositionModal] = useState(false)
  // Pre-selected pool for new position (from clicking a pool in the list)
  const [selectedPoolForPosition, setSelectedPoolForPosition] = useState<PoolInfo | null>(null)
  // Selected pool for swap quote (fee + tickSpacing + pair)
  const [selectedPool, setSelectedPool] = useState<{
    poolId: string
    currency0: string
    currency1: string
    fee: number
    tickSpacing: number
    symbol0: string
    symbol1: string
  } | null>(null)

  const quoterAddress = getQuoterAddress()

  // Handle pool selection (from Pool or Explore): set swap context, go to Pool tab, open new position modal
  const handleSelectPool = useCallback((pool: PoolInfo) => {
    const t0 = tokenOptions.find((t) => t.symbol === pool.symbol0) ?? tokenOptions[0]!
    const t1 = tokenOptions.find((t) => t.symbol === pool.symbol1) ?? tokenOptions[1]!
    setSelectedPool({
      poolId: pool.poolId,
      currency0: pool.currency0,
      currency1: pool.currency1,
      fee: pool.fee,
      tickSpacing: pool.tickSpacing,
      symbol0: pool.symbol0,
      symbol1: pool.symbol1,
    })
    setTokenIn(t0)
    setTokenOut(t1)
    setSelectedPoolForPosition(pool)
    setTab(TAB.POOL)
    setShowNewPositionModal(true)
  }, [tokenOptions])

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
    const addrIn = resolveAddress(tokenIn)
    const addrOut = resolveAddress(tokenOut)
    if (!addrIn || !addrOut || addrIn === addrOut) {
      setAmountOut('')
      setQuoteError(null)
      setQuoteLoading(false)
      return
    }

    const currency0 = addrIn < addrOut ? addrIn : addrOut
    const currency1 = addrIn < addrOut ? addrOut : addrIn
    const zeroForOne = addrIn < addrOut
    const useSelected =
      selectedPool &&
      selectedPool.currency0.toLowerCase() === currency0.toLowerCase() &&
      selectedPool.currency1.toLowerCase() === currency1.toLowerCase()
    const fee = useSelected ? selectedPool.fee : DEFAULT_FEE
    const tickSpacing = useSelected ? selectedPool.tickSpacing : DEFAULT_TICK_SPACING
    const poolKey = { currency0, currency1, fee, tickSpacing }
    const decimalsIn = resolveDecimals(tokenIn)
    const decimalsOut = resolveDecimals(tokenOut)

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
          client as import('viem').PublicClient,
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
  }, [amountIn, tokenIn.symbol, tokenOut.symbol, quoterAddress, selectedPool])

  const flipTokens = () => {
    setTokenIn(tokenOut)
    setTokenOut(tokenIn)
    setAmountIn(amountOut)
    setAmountOut('') // re-quote will fill from Quoter
  }

  return (
    <div className="app">
      <header className="header">
        <span className="logo">HieroForge</span>
        <nav className="nav nav--uniswap">
          <button
            className={`nav-btn ${tab === TAB.TRADE ? 'active' : ''}`}
            onClick={() => setTab(TAB.TRADE)}
          >
            Trade
          </button>
          <button
            className={`nav-btn ${tab === TAB.EXPLORE ? 'active' : ''}`}
            onClick={() => setTab(TAB.EXPLORE)}
          >
            Explore
          </button>
          <button
            className={`nav-btn ${tab === TAB.POOL ? 'active' : ''}`}
            onClick={() => setTab(TAB.POOL)}
          >
            Pool
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

      <main className={`main ${tab === TAB.POOL ? 'main--pool-tab' : ''} ${tab === TAB.EXPLORE ? 'main--explore-tab' : ''}`}>
        {tab === TAB.TRADE && (
          <div className={`card card--swap ${quoteError ? 'card--error' : ''}`}>
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
                <div className="token-select-wrap">
                  <TokenIcon symbol={tokenIn.symbol} size={28} />
                  <select
                    className="token-select"
                    value={tokenIn.id}
                    onChange={(e) =>
                      setTokenIn(tokenOptions.find((t) => t.id === e.target.value) ?? tokenOptions[0]!)
                    }
                    disabled={tokensLoading}
                  >
                    {tokenOptions.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.symbol}
                      </option>
                    ))}
                  </select>
                </div>
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
                <div className="token-select-wrap">
                  <TokenIcon symbol={tokenOut.symbol} size={28} />
                  <select
                    className="token-select"
                    value={tokenOut.id}
                    onChange={(e) =>
                      setTokenOut(tokenOptions.find((t) => t.id === e.target.value) ?? tokenOptions[1]!)
                    }
                    disabled={tokensLoading}
                  >
                    {tokenOptions.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.symbol}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            </div>
            {quoteError && (
              <ErrorMessage id="quote-error-msg" message={quoteError} className="quote-error" />
            )}
            <p className="helper">Concentrated liquidity · Price limit optional</p>
            {quoterAddress ? (
              <p className="helper">Live quote from Quoter (exact input). Tokens loaded from DynamoDB.</p>
            ) : (
              <p className="helper">Set NEXT_PUBLIC_QUOTER_ADDRESS in .env.local to see quoted output.</p>
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

        {tab === TAB.EXPLORE && (
          <Explore onSelectPool={handleSelectPool} />
        )}

        {tab === TAB.POOL && (
          <PoolPositions
            onCreatePosition={() => { setSelectedPoolForPosition(null); setShowNewPositionModal(true) }}
            onSelectPool={handleSelectPool}
          />
        )}

        {/* New position form in modal (HTS token pair + fee) */}
        {showNewPositionModal && (
          <div className="new-position-modal-overlay" onClick={() => setShowNewPositionModal(false)}>
            <div className="new-position-modal" onClick={(e) => e.stopPropagation()}>
              <button type="button" className="new-position-modal-close" onClick={() => setShowNewPositionModal(false)} aria-label="Close">×</button>
              <NewPosition
                onBack={() => setShowNewPositionModal(false)}
                preselectedPool={selectedPoolForPosition}
              />
            </div>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
