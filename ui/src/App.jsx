import { useState, useCallback } from 'react'
import { createWalletClient, custom } from 'viem'
import './App.css'
import { useHashPack } from './context/HashPackContext.jsx'
import { PoolManagerAbi, SQRT_PRICE_PRESETS } from './abis/PoolManager.js'

const TAB = { SWAP: 'swap', POOL: 'pool', LIQUIDITY: 'liquidity' }

// Hedera testnet
const hederaTestnet = {
  id: 296,
  name: 'Hedera Testnet',
  nativeCurrency: { name: 'HBAR', symbol: 'HBAR', decimals: 8 },
  rpcUrls: { default: { http: ['https://testnet.hashio.io/api'] } },
  blockExplorers: { default: { name: 'HashScan', url: 'https://hashscan.io/testnet' } },
}

const DEFAULT_TOKENS = [
  { id: 'token0', symbol: 'HBAR' },
  { id: 'token1', symbol: 'USDC' },
  { id: 'token2', symbol: 'TokenA' },
]

function App() {
  const [tab, setTab] = useState(TAB.SWAP)
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
  const [tokenIn, setTokenIn] = useState(DEFAULT_TOKENS[0])
  const [tokenOut, setTokenOut] = useState(DEFAULT_TOKENS[1])

  // Add liquidity state
  const [tickLower, setTickLower] = useState('-60')
  const [tickUpper, setTickUpper] = useState('60')
  const [liquidityAmount, setLiquidityAmount] = useState('')
  const [liquidityToken0, setLiquidityToken0] = useState(DEFAULT_TOKENS[0])
  const [liquidityToken1, setLiquidityToken1] = useState(DEFAULT_TOKENS[1])

  // Create pool state
  const [token0Address, setToken0Address] = useState('')
  const [token1Address, setToken1Address] = useState('')
  const [fee, setFee] = useState('3000')
  const [tickSpacing, setTickSpacing] = useState('60')
  const [initialPriceKey, setInitialPriceKey] = useState('1')
  const [createPoolTx, setCreatePoolTx] = useState(null)
  const [createPoolError, setCreatePoolError] = useState(null)
  const [createPoolPending, setCreatePoolPending] = useState(false)

  const poolManagerAddress = import.meta.env.VITE_POOL_MANAGER_ADDRESS || ''

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
    const sqrtPriceX96 = BigInt(SQRT_PRICE_PRESETS[initialPriceKey] || SQRT_PRICE_PRESETS['1'])
    const poolKey = { currency0, currency1, fee: feeNum, tickSpacing: tickSpacingNum, hooks: '0x0000000000000000000000000000000000000000' }

    const provider = typeof window !== 'undefined' && window.ethereum
    if (!provider) {
      setCreatePoolError('No EVM wallet found. Install MetaMask or use an EVM-compatible wallet on Hedera Testnet.')
      return
    }

    setCreatePoolError(null)
    setCreatePoolPending(true)
    setCreatePoolTx(null)
    try {
      const chainId = Number(import.meta.env.VITE_CHAIN_ID || '296')
      const walletClient = createWalletClient({ chain: hederaTestnet, transport: custom(provider) })
      const [address] = await walletClient.requestAddresses()
      if (!address) {
        setCreatePoolError('Connect your EVM wallet first.')
        setCreatePoolPending(false)
        return
      }
      const hash = await walletClient.writeContract({
        address: poolManagerAddress,
        abi: PoolManagerAbi,
        functionName: 'initialize',
        args: [poolKey, sqrtPriceX96],
        account: address,
      })
      setCreatePoolTx({ hash })
    } catch (err) {
      setCreatePoolError(err?.shortMessage || err?.message || 'Transaction failed.')
    } finally {
      setCreatePoolPending(false)
    }
  }, [poolManagerAddress, token0Address, token1Address, fee, tickSpacing, initialPriceKey])

  const flipTokens = () => {
    setTokenIn(tokenOut)
    setTokenOut(tokenIn)
    setAmountIn(amountOut)
    setAmountOut(amountIn)
  }

  // Mock pools for display
  const pools = [
    { id: '1', pair: 'HBAR / USDC', tickSpacing: 60, fee: '0.3%' },
    { id: '2', pair: 'TokenA / USDC', tickSpacing: 60, fee: '0.3%' },
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
        {error && <span className="header-error">{error}</span>}
        <button
          className={`connect-btn ${isConnected ? 'connected' : ''}`}
          onClick={() => (isConnected ? disconnect() : connect())}
          disabled={isConnecting || !isInitialized}
        >
          {isConnecting
            ? 'Connecting...'
            : isConnected
              ? formattedAccountId || accountId
              : 'Connect HashPack'}
        </button>
      </header>

      <main className="main">
        {tab === TAB.SWAP && (
          <div className="card">
            <h2 className="card-title">Swap</h2>
            <div className="token-row">
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
                    setTokenIn(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
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
            <div className="token-row">
              <div className="token-row-label">You receive</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder="0.0"
                  value={amountOut}
                  onChange={(e) => setAmountOut(e.target.value)}
                />
                <select
                  className="token-select"
                  value={tokenOut.id}
                  onChange={(e) =>
                    setTokenOut(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
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
            <p className="helper">Concentrated liquidity · Price limit optional</p>
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
                {Object.entries(SQRT_PRICE_PRESETS).map(([k]) => (
                  <option key={k} value={k}>{k}</option>
                ))}
              </select>
            </div>
            {createPoolError && <p className="header-error create-pool-err">{createPoolError}</p>}
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
            <div className="form-group">
              <label>Token pair</label>
              <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
                <select
                  className="token-select"
                  style={{ flex: 1 }}
                  value={liquidityToken0.id}
                  onChange={(e) =>
                    setLiquidityToken0(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
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
                    setLiquidityToken1(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
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
                onChange={(e) => setLiquidityAmount(e.target.value)}
                placeholder="0"
              />
            </div>
            <p className="helper">
              Liquidity is provided in the selected tick range. Must be multiple of tick spacing.
            </p>
            <button
              type="button"
              className="primary-btn"
              disabled={!liquidityAmount || !isConnected}
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
