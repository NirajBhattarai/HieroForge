'use client'

import { useState, useCallback, useEffect, useRef } from 'react'
import { createPublicClient, http, parseUnits, encodeFunctionData, type PublicClient } from 'viem'
import { TokenIcon } from './TokenIcon'
import { ErrorMessage } from './ErrorMessage'
import { buildPoolKey, getPoolId, encodeUnlockDataMint } from '@/lib/addLiquidity'
import { tickToPrice, priceToTick, roundToTickSpacing, PRICE_STRATEGIES } from '@/lib/priceUtils'
import { getFriendlyErrorMessage } from '@/lib/errors'
import { PoolManagerAbi, SQRT_PRICE_PRESETS } from '@/abis/PoolManager'
import { PositionManagerAbi, SQRT_PRICE_1_1 } from '@/abis/PositionManager'
import { ERC20Abi } from '@/abis/ERC20'
import {
  DEFAULT_TOKENS,
  getTokenAddress,
  getTokenDecimals,
  getPoolManagerAddress,
  getPositionManagerAddress,
  HEDERA_TESTNET,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  type TokenOption,
} from '@/constants'
import { useTokens, type DynamicToken } from '@/hooks/useTokens'
import { useTokenLookup } from '@/hooks/useTokenLookup'
import type { PoolInfo } from './PoolPositions'

type Step = 1 | 2

interface NewPositionProps {
  onBack: () => void
  /** Pre-selected pool from "View positions" click */
  preselectedPool?: PoolInfo | null
}

const FEE_TIERS = [
  { fee: 500, label: '0.05%', desc: 'Best for stable pairs' },
  { fee: 3000, label: '0.3%', desc: 'Best for most pairs', tag: 'Most used' },
  { fee: 10000, label: '1%', desc: 'Best for exotic pairs' },
] as const

function feeTierToTickSpacing(fee: number): number {
  if (fee === 500) return 10
  if (fee === 10000) return 200
  return 60
}

export function NewPosition({ onBack, preselectedPool }: NewPositionProps) {
  const [step, setStep] = useState<Step>(1)

  // Dynamic token list from DynamoDB
  const { tokens: dynamicTokens, loading: tokensLoading, refetch: refetchTokens } = useTokens()
  const tokenOptions: TokenOption[] = dynamicTokens.length > 0
    ? dynamicTokens.map((t) => ({ id: t.address, symbol: t.symbol, address: t.address, decimals: t.decimals, name: t.name }))
    : DEFAULT_TOKENS

  // Helper: resolve address from TokenOption (prefers .address field, falls back to static lookup)
  const resolveAddress = (tok: TokenOption): string =>
    (tok.address ?? getTokenAddress(tok.symbol)).toLowerCase()
  const resolveDecimals = (tok: TokenOption): number =>
    tok.decimals ?? getTokenDecimals(tok.symbol)

  // Step 1: pair + fee
  const [token0, setToken0] = useState<TokenOption>(DEFAULT_TOKENS[0]!)
  const [token1, setToken1] = useState<TokenOption>(DEFAULT_TOKENS[1]!)
  const [token0Addr, setToken0Addr] = useState('')
  const [token1Addr, setToken1Addr] = useState('')
  const [fee, setFee] = useState(DEFAULT_FEE)
  const [tickSpacing, setTickSpacing] = useState(DEFAULT_TICK_SPACING)
  const [showMoreFees, setShowMoreFees] = useState(false)

  // Token address auto-lookup
  const { token: resolved0, loading: lookup0Loading, error: lookup0Error } = useTokenLookup(token0Addr)
  const { token: resolved1, loading: lookup1Loading, error: lookup1Error } = useTokenLookup(token1Addr)

  // Step 2: price range + deposits
  const [minPriceStr, setMinPriceStr] = useState('0.9')
  const [maxPriceStr, setMaxPriceStr] = useState('1.1')
  const [tickLower, setTickLower] = useState(-60)
  const [tickUpper, setTickUpper] = useState(60)
  const [amount0, setAmount0] = useState('')
  const [amount1, setAmount1] = useState('')
  const [liquidityAmount, setLiquidityAmount] = useState('100000000')
  const currentPriceRef = 1 // 1:1 for new pool; upgrade later with getPoolState

  // Pool state
  const [poolInitialized, setPoolInitialized] = useState<boolean | null>(null)

  // TX state
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [txHash, setTxHash] = useState<string | null>(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [savePending, setSavePending] = useState(false)

  const poolManagerAddress = getPoolManagerAddress()
  const positionManagerAddress = getPositionManagerAddress()

  const publicClientRef = useRef<PublicClient | null>(null)
  if (!publicClientRef.current && typeof window !== 'undefined') {
    publicClientRef.current = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(HEDERA_TESTNET.rpcUrls.default.http[0]),
    }) as PublicClient
  }

  // Restore from preselected pool
  useEffect(() => {
    if (!preselectedPool) {
      // Set defaults from dynamic list when it loads
      if (tokenOptions.length >= 2) {
        setToken0(tokenOptions[0]!)
        setToken1(tokenOptions[1]!)
      }
      return
    }
    const t0 = tokenOptions.find((t) => t.symbol === preselectedPool.symbol0) ?? tokenOptions[0]!
    const t1 = tokenOptions.find((t) => t.symbol === preselectedPool.symbol1) ?? tokenOptions[1]!
    setToken0(t0)
    setToken1(t1)
    setToken0Addr(preselectedPool.currency0)
    setToken1Addr(preselectedPool.currency1)
    setFee(preselectedPool.fee)
    setTickSpacing(preselectedPool.tickSpacing)
  }, [preselectedPool, tokenOptions.length])

  // Update addresses when dropdowns change
  useEffect(() => {
    setToken0Addr(resolveAddress(token0))
  }, [token0])
  useEffect(() => {
    setToken1Addr(resolveAddress(token1))
  }, [token1])

  // Sync resolved on-chain token data back into token state
  useEffect(() => {
    if (resolved0) {
      const addr = resolved0.address.toLowerCase()
      if (token0.address?.toLowerCase() !== addr || token0.symbol !== resolved0.symbol) {
        setToken0({ id: addr, symbol: resolved0.symbol, address: addr, decimals: resolved0.decimals, name: resolved0.name })
        refetchTokens()
      }
      // Normalize address input to EVM hex (e.g. if user pasted 0.0.XXXXX)
      if (token0Addr.toLowerCase() !== addr) setToken0Addr(addr)
    }
  }, [resolved0])
  useEffect(() => {
    if (resolved1) {
      const addr = resolved1.address.toLowerCase()
      if (token1.address?.toLowerCase() !== addr || token1.symbol !== resolved1.symbol) {
        setToken1({ id: addr, symbol: resolved1.symbol, address: addr, decimals: resolved1.decimals, name: resolved1.name })
        refetchTokens()
      }
      if (token1Addr.toLowerCase() !== addr) setToken1Addr(addr)
    }
  }, [resolved1])

  // Check pool initialized state
  useEffect(() => {
    if (!poolManagerAddress || !publicClientRef.current) { setPoolInitialized(null); return }
    const addr0 = token0Addr || resolveAddress(token0)
    const addr1 = token1Addr || resolveAddress(token1)
    if (!addr0 || !addr1 || addr0 === addr1) { setPoolInitialized(null); return }
    const poolKey = buildPoolKey(addr0 as `0x${string}`, addr1 as `0x${string}`, fee, tickSpacing)
    const poolId = getPoolId(poolKey)
    let cancelled = false
    publicClientRef.current
      .readContract({
        address: poolManagerAddress as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: 'getPoolState',
        args: [poolId],
      })
      .then((value: unknown) => {
        if (!cancelled) setPoolInitialized((value as readonly [boolean, bigint, number])[0])
      })
      .catch(() => {
        if (!cancelled) setPoolInitialized(false)
      })
    return () => { cancelled = true }
  }, [poolManagerAddress, token0Addr, token1Addr, token0.symbol, token1.symbol, fee, tickSpacing])

  const syncPriceToTicks = useCallback(() => {
    const minP = parseFloat(minPriceStr)
    const maxP = parseFloat(maxPriceStr)
    if (!Number.isFinite(minP) || !Number.isFinite(maxP)) return
    setTickLower(roundToTickSpacing(priceToTick(minP), tickSpacing))
    setTickUpper(roundToTickSpacing(priceToTick(maxP), tickSpacing))
  }, [minPriceStr, maxPriceStr, tickSpacing])

  const applyStrategy = (strategy: (typeof PRICE_STRATEGIES)[number]) => {
    const ref = currentPriceRef
    if ('tickDelta' in strategy && strategy.tickDelta !== undefined) {
      const centerTick = roundToTickSpacing(priceToTick(ref), tickSpacing)
      const delta = strategy.tickDelta * tickSpacing
      setTickLower(centerTick - delta)
      setTickUpper(centerTick + delta)
      setMinPriceStr(tickToPrice(centerTick - delta).toFixed(4))
      setMaxPriceStr(tickToPrice(centerTick + delta).toFixed(4))
      return
    }
    const minPct = 'minPct' in strategy ? strategy.minPct ?? 0 : 0
    const maxPct = 'maxPct' in strategy ? strategy.maxPct ?? 0 : 0
    setMinPriceStr((ref * (1 + minPct)).toFixed(4))
    setMaxPriceStr((ref * (1 + maxPct)).toFixed(4))
    setTickLower(roundToTickSpacing(priceToTick(ref * (1 + minPct)), tickSpacing))
    setTickUpper(roundToTickSpacing(priceToTick(ref * (1 + maxPct)), tickSpacing))
  }

  const adjustMinPrice = (delta: number) => {
    const p = parseFloat(minPriceStr) || currentPriceRef
    const newP = p * (1 + delta)
    setMinPriceStr(newP.toFixed(4))
    setTickLower(roundToTickSpacing(priceToTick(newP), tickSpacing))
  }
  const adjustMaxPrice = (delta: number) => {
    const p = parseFloat(maxPriceStr) || currentPriceRef
    const newP = p * (1 + delta)
    setMaxPriceStr(newP.toFixed(4))
    setTickUpper(roundToTickSpacing(priceToTick(newP), tickSpacing))
  }

  const canContinue = () => {
    const a0 = token0Addr || resolveAddress(token0)
    const a1 = token1Addr || resolveAddress(token1)
    return a0 && a1 && a0 !== a1
  }

  // Create pool only (PoolManager.initialize)
  const createPoolOnly = useCallback(async () => {
    const addr0 = (token0Addr || resolveAddress(token0)).trim()
    const addr1 = (token1Addr || resolveAddress(token1)).trim()
    if (!addr0 || !addr1 || addr0 === addr1) { setError('Select two different tokens.'); return }
    if (!poolManagerAddress) { setError('PoolManager address not configured.'); return }

    const provider = typeof window !== 'undefined' && (window as unknown as { ethereum?: unknown }).ethereum
    if (!provider) { setError('No EVM wallet found.'); return }

    setError(null); setPending(true); setTxHash(null)
    try {
      const { createWalletClient, custom } = await import('viem')
      const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport: custom(provider as Parameters<typeof custom>[0]) })
      const [address] = await walletClient.requestAddresses()
      if (!address) { setError('Connect wallet first.'); setPending(false); return }

      const currency0 = addr0.toLowerCase() < addr1.toLowerCase() ? addr0 : addr1
      const currency1 = addr0.toLowerCase() < addr1.toLowerCase() ? addr1 : addr0
      const poolKey = { currency0, currency1, fee, tickSpacing, hooks: '0x0000000000000000000000000000000000000000' as const }
      const sqrtPriceX96 = BigInt(SQRT_PRICE_PRESETS['1'] ?? '79228162514264337593543950336')

      const hash = await walletClient.writeContract({
        address: poolManagerAddress as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: 'initialize',
        args: [poolKey, sqrtPriceX96],
        account: address,
      })
      setTxHash(hash)
      setPoolInitialized(true)
    } catch (err: unknown) {
      setError(getFriendlyErrorMessage(err, 'transaction'))
    } finally {
      setPending(false)
    }
  }, [poolManagerAddress, token0Addr, token1Addr, token0.symbol, token1.symbol, fee, tickSpacing])

  // Add liquidity (approve + transfer + multicall: initializePool + modifyLiquidities)
  const addLiquidity = useCallback(async () => {
    if (!positionManagerAddress) { setError('Set NEXT_PUBLIC_POSITION_MANAGER_ADDRESS in .env.local.'); return }
    const addr0 = (token0Addr || resolveAddress(token0)).trim()
    const addr1 = (token1Addr || resolveAddress(token1)).trim()
    if (!addr0 || !addr1 || addr0 === addr1) { setError('Select two different tokens.'); return }

    const provider = typeof window !== 'undefined' && (window as unknown as { ethereum?: unknown }).ethereum
    if (!provider) { setError('No EVM wallet found.'); return }

    const dec0 = resolveDecimals(token0)
    const dec1 = resolveDecimals(token1)
    let amount0Wei: bigint, amount1Wei: bigint, liquidityWei: bigint
    try {
      amount0Wei = parseUnits(amount0 || '0', dec0)
      amount1Wei = parseUnits(amount1 || '0', dec1)
      liquidityWei = BigInt(liquidityAmount || '0')
    } catch { setError('Invalid amount.'); return }
    if (amount0Wei === 0n && amount1Wei === 0n) { setError('Enter amount for at least one token.'); return }
    if (liquidityWei === 0n) { setError('Enter liquidity amount.'); return }

    setError(null); setPending(true); setTxHash(null)
    try {
      const { createWalletClient, custom } = await import('viem')
      const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport: custom(provider as Parameters<typeof custom>[0]) })
      const [userAddress] = await walletClient.requestAddresses()
      if (!userAddress) { setError('Connect wallet first.'); setPending(false); return }

      const poolKey = buildPoolKey(addr0 as `0x${string}`, addr1 as `0x${string}`, fee, tickSpacing)
      const pmAddr = positionManagerAddress as `0x${string}`
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600)
      const unlockData = encodeUnlockDataMint(poolKey, tickLower, tickUpper, liquidityWei, amount0Wei, amount1Wei, userAddress)

      // Approve + transfer for each token
      for (const [currency, amountWei] of [[poolKey.currency0, amount0Wei], [poolKey.currency1, amount1Wei]] as const) {
        if (amountWei > 0n) {
          const allowance = (await publicClientRef.current!.readContract({
            address: currency as `0x${string}`, abi: ERC20Abi, functionName: 'allowance', args: [userAddress, pmAddr],
          })) as bigint
          if (allowance < amountWei) {
            const h = await walletClient.writeContract({
              address: currency as `0x${string}`, abi: ERC20Abi, functionName: 'approve', args: [pmAddr, amountWei], account: userAddress,
            })
            await publicClientRef.current!.waitForTransactionReceipt({ hash: h })
          }
          await walletClient.writeContract({
            address: currency as `0x${string}`, abi: ERC20Abi, functionName: 'transfer', args: [pmAddr, amountWei], account: userAddress,
          })
        }
      }

      // Multicall: initializePool + modifyLiquidities
      const initCalldata = encodeFunctionData({ abi: PositionManagerAbi, functionName: 'initializePool', args: [poolKey, SQRT_PRICE_1_1] })
      const modifyCalldata = encodeFunctionData({ abi: PositionManagerAbi, functionName: 'modifyLiquidities', args: [unlockData, deadline] })
      const hash = await walletClient.writeContract({
        address: pmAddr, abi: PositionManagerAbi, functionName: 'multicall', args: [[initCalldata, modifyCalldata]], account: userAddress,
      })
      setTxHash(hash)
    } catch (err: unknown) {
      setError(getFriendlyErrorMessage(err, 'transaction'))
    } finally {
      setPending(false)
    }
  }, [positionManagerAddress, token0Addr, token1Addr, token0.symbol, token1.symbol, fee, tickSpacing, tickLower, tickUpper, amount0, amount1, liquidityAmount])

  // Save pool to DynamoDB
  const savePool = useCallback(async () => {
    const addr0 = (token0Addr || resolveAddress(token0)).trim()
    const addr1 = (token1Addr || resolveAddress(token1)).trim()
    if (!addr0 || !addr1 || addr0 === addr1) return
    const poolKey = buildPoolKey(addr0 as `0x${string}`, addr1 as `0x${string}`, fee, tickSpacing)
    const poolId = getPoolId(poolKey)
    setSavePending(true); setSaveSuccess(false)
    try {
      const res = await fetch('/api/pools', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          poolId, currency0: poolKey.currency0, currency1: poolKey.currency1,
          fee, tickSpacing, symbol0: token0.symbol, symbol1: token1.symbol,
        }),
      })
      if (!res.ok) throw new Error('Failed to save pool')
      setSaveSuccess(true)
    } catch { /* ignore */ }
    finally { setSavePending(false) }
  }, [token0Addr, token1Addr, token0.symbol, token1.symbol, fee, tickSpacing])

  return (
    <div className="new-position-page">
      {/* Breadcrumb */}
      <div className="np-breadcrumb">
        <button type="button" className="np-breadcrumb-link" onClick={onBack}>Your positions</button>
        <span className="np-breadcrumb-sep">›</span>
        <span>New position</span>
      </div>

      <div className="np-header">
        <h2 className="np-title">New position</h2>
        <span className="np-version-badge">v4 position</span>
      </div>

      <div className="np-layout">
        {/* Left: Steps indicator */}
        <div className="np-steps">
          <div className={`np-step ${step >= 1 ? 'np-step--active' : ''}`}>
            <div className="np-step-number">1</div>
            <div className="np-step-text">
              <span className="np-step-label">Step 1</span>
              <span className="np-step-desc">Select token pair and fees</span>
            </div>
          </div>
          <div className={`np-step ${step >= 2 ? 'np-step--active' : ''}`}>
            <div className="np-step-number">2</div>
            <div className="np-step-text">
              <span className="np-step-label">Step 2</span>
              <span className="np-step-desc">Set price range and deposit amounts</span>
            </div>
          </div>
        </div>

        {/* Right: Current step content */}
        <div className="np-content">
          {step === 1 && (
            <div className="np-step1">
              <h3 className="np-section-title">Select pair</h3>
              <p className="np-section-desc">Choose the tokens you want to provide liquidity for.</p>

              <div className="np-pair-row">
                <div className="np-token-select">
                  <TokenIcon symbol={resolved0?.symbol ?? token0.symbol} size={28} />
                  <select
                    value={token0.id}
                    onChange={(e) => setToken0(tokenOptions.find((t) => t.id === e.target.value) ?? tokenOptions[0]!)}
                    disabled={tokensLoading}
                  >
                    {tokenOptions.map((t) => <option key={t.id} value={t.id}>{t.symbol}</option>)}
                  </select>
                </div>
                <div className="np-token-select">
                  <TokenIcon symbol={resolved1?.symbol ?? token1.symbol} size={28} />
                  <select
                    value={token1.id}
                    onChange={(e) => setToken1(tokenOptions.find((t) => t.id === e.target.value) ?? tokenOptions[1]!)}
                    disabled={tokensLoading}
                  >
                    {tokenOptions.map((t) => <option key={t.id} value={t.id}>{t.symbol}</option>)}
                  </select>
                </div>
              </div>

              {/* Paste addresses — auto-detects token on-chain */}
              <div className="np-addr-inputs">
                <div className="np-addr-group">
                  <label>Token 0 address</label>
                  <input
                    type="text"
                    className="np-addr-input"
                    placeholder="0x... paste any token address"
                    value={token0Addr}
                    onChange={(e) => setToken0Addr(e.target.value)}
                  />
                  <div className="np-addr-status">
                    {lookup0Loading && <span className="np-addr-loading">Looking up token…</span>}
                    {lookup0Error && <span className="np-addr-error">{lookup0Error}</span>}
                    {resolved0 && !lookup0Loading && (
                      <span className="np-addr-resolved">
                        <TokenIcon symbol={resolved0.symbol} size={16} />
                        ✓ {resolved0.symbol} — {resolved0.name} ({resolved0.decimals} decimals){resolved0.isHts ? ' · HTS' : ''}
                      </span>
                    )}
                  </div>
                </div>
                <div className="np-addr-group">
                  <label>Token 1 address</label>
                  <input
                    type="text"
                    className="np-addr-input"
                    placeholder="0x... paste any token address"
                    value={token1Addr}
                    onChange={(e) => setToken1Addr(e.target.value)}
                  />
                  <div className="np-addr-status">
                    {lookup1Loading && <span className="np-addr-loading">Looking up token…</span>}
                    {lookup1Error && <span className="np-addr-error">{lookup1Error}</span>}
                    {resolved1 && !lookup1Loading && (
                      <span className="np-addr-resolved">
                        <TokenIcon symbol={resolved1.symbol} size={16} />
                        ✓ {resolved1.symbol} — {resolved1.name} ({resolved1.decimals} decimals){resolved1.isHts ? ' · HTS' : ''}
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Fee tier */}
              <h3 className="np-section-title np-section-title--mt">Fee tier</h3>
              <p className="np-section-desc">The fee earned providing liquidity. Choose an amount that suits your risk tolerance.</p>

              <div className="np-fee-main">
                <div
                  className={`np-fee-card ${fee === 3000 ? 'np-fee-card--selected' : ''}`}
                  onClick={() => { setFee(3000); setTickSpacing(60) }}
                >
                  <span className="np-fee-pct">0.3% fee tier</span>
                  {fee === 3000 && <span className="np-fee-tag">Selected</span>}
                  <span className="np-fee-desc">The % you will earn in fees</span>
                </div>
                <button type="button" className="np-fee-more-btn" onClick={() => setShowMoreFees(!showMoreFees)}>
                  {showMoreFees ? 'Less' : 'More'} ▾
                </button>
              </div>
              {showMoreFees && (
                <div className="np-fee-grid">
                  {FEE_TIERS.map((tier) => (
                    <div
                      key={tier.fee}
                      className={`np-fee-card np-fee-card--sm ${fee === tier.fee ? 'np-fee-card--selected' : ''}`}
                      onClick={() => { setFee(tier.fee); setTickSpacing(feeTierToTickSpacing(tier.fee)) }}
                    >
                      <span className="np-fee-pct">{tier.label}</span>
                      {'tag' in tier && tier.tag && <span className="np-fee-tag">{tier.tag}</span>}
                      <span className="np-fee-desc">{tier.desc}</span>
                    </div>
                  ))}
                </div>
              )}

              {poolInitialized !== null && (
                <div className={`np-pool-status ${poolInitialized ? 'np-pool-status--active' : 'np-pool-status--new'}`}>
                  {poolInitialized ? '✓ Pool exists — you will add liquidity' : '⚡ New pool — will be created at 1:1 price'}
                </div>
              )}

              <button
                type="button"
                className="np-continue-btn"
                disabled={!canContinue()}
                onClick={() => { syncPriceToTicks(); setStep(2) }}
              >
                Continue
              </button>
            </div>
          )}

          {step === 2 && (
            <div className="np-step2">
              <button type="button" className="np-back-step" onClick={() => setStep(1)}>
                ← Back to Step 1
              </button>

              {/* Price strategies */}
              <h3 className="np-section-title">Price range</h3>
              <p className="np-section-desc">Set your price range. Narrower ranges earn more fees but require more active management.</p>

              <div className="np-strategy-row">
                {PRICE_STRATEGIES.map((s) => (
                  <button
                    key={s.id}
                    type="button"
                    className="np-strategy-chip"
                    onClick={() => applyStrategy(s)}
                  >
                    {s.label}
                  </button>
                ))}
              </div>

              <div className="np-price-range">
                <div className="np-price-box">
                  <label>Min price</label>
                  <div className="np-price-input-wrap">
                    <button type="button" className="np-price-adj" onClick={() => adjustMinPrice(-0.01)}>−</button>
                    <input
                      type="text"
                      className="np-price-input"
                      value={minPriceStr}
                      onChange={(e) => { setMinPriceStr(e.target.value); setTimeout(syncPriceToTicks, 0) }}
                      onBlur={syncPriceToTicks}
                    />
                    <button type="button" className="np-price-adj" onClick={() => adjustMinPrice(0.01)}>+</button>
                  </div>
                  <span className="np-price-sub">{token1.symbol} per {token0.symbol}</span>
                </div>
                <div className="np-price-box">
                  <label>Max price</label>
                  <div className="np-price-input-wrap">
                    <button type="button" className="np-price-adj" onClick={() => adjustMaxPrice(-0.01)}>−</button>
                    <input
                      type="text"
                      className="np-price-input"
                      value={maxPriceStr}
                      onChange={(e) => { setMaxPriceStr(e.target.value); setTimeout(syncPriceToTicks, 0) }}
                      onBlur={syncPriceToTicks}
                    />
                    <button type="button" className="np-price-adj" onClick={() => adjustMaxPrice(0.01)}>+</button>
                  </div>
                  <span className="np-price-sub">{token1.symbol} per {token0.symbol}</span>
                </div>
              </div>

              {/* Deposit amounts */}
              <h3 className="np-section-title np-section-title--mt">Deposit amounts</h3>
              <div className="np-deposit-row">
                <div className="np-deposit-box">
                  <div className="np-deposit-header">
                    <TokenIcon symbol={token0.symbol} size={20} />
                    <span>{token0.symbol}</span>
                  </div>
                  <input
                    type="text"
                    className="np-deposit-input"
                    placeholder="0.0"
                    value={amount0}
                    onChange={(e) => { setAmount0(e.target.value); setError(null) }}
                  />
                </div>
                <div className="np-deposit-box">
                  <div className="np-deposit-header">
                    <TokenIcon symbol={token1.symbol} size={20} />
                    <span>{token1.symbol}</span>
                  </div>
                  <input
                    type="text"
                    className="np-deposit-input"
                    placeholder="0.0"
                    value={amount1}
                    onChange={(e) => { setAmount1(e.target.value); setError(null) }}
                  />
                </div>
              </div>

              <div className="np-liquidity-row">
                <label>Liquidity (L)</label>
                <input
                  type="text"
                  className="np-liquidity-input"
                  value={liquidityAmount}
                  onChange={(e) => { setLiquidityAmount(e.target.value); setError(null) }}
                  placeholder="100000000"
                />
              </div>

              {/* Errors / success */}
              {error && <ErrorMessage message={error} className="np-error" onDismiss={() => setError(null)} />}
              {txHash && (
                <div className="np-success">
                  Transaction sent!{' '}
                  <a href={`https://hashscan.io/testnet/transaction/${txHash}`} target="_blank" rel="noreferrer">View on HashScan →</a>
                </div>
              )}

              {/* Actions */}
              <div className="np-actions">
                {!positionManagerAddress && poolManagerAddress && (
                  <button
                    type="button"
                    className="np-action-btn np-action-btn--secondary"
                    disabled={pending}
                    onClick={createPoolOnly}
                  >
                    {pending ? 'Creating...' : 'Create pool only'}
                  </button>
                )}
                <button
                  type="button"
                  className="np-action-btn np-action-btn--primary"
                  disabled={pending || (!amount0 && !amount1) || !positionManagerAddress}
                  onClick={addLiquidity}
                >
                  {pending
                    ? 'Processing...'
                    : poolInitialized === false
                      ? 'Create pool & add liquidity'
                      : 'Add liquidity'}
                </button>
              </div>

              {!positionManagerAddress && (
                <p className="np-warning">Set NEXT_PUBLIC_POSITION_MANAGER_ADDRESS in .env.local to add liquidity.</p>
              )}

              {/* Save to DynamoDB */}
              <div className="np-save-section">
                <button
                  type="button"
                  className="np-save-btn"
                  disabled={savePending || !canContinue()}
                  onClick={savePool}
                >
                  {savePending ? 'Saving...' : saveSuccess ? '✓ Saved to pool list' : 'Save pool to list'}
                </button>
                <span className="np-save-hint">Save to DynamoDB so you can load it later</span>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
