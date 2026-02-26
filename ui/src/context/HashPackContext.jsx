import { createContext, useContext, useState, useEffect, useCallback, useRef } from 'react'
import { HashConnect } from 'hashconnect'
import { LedgerId } from '@hashgraph/sdk'
import { ModalCtrl } from '@walletconnect/modal-core'

const HashPackContext = createContext(null)

const APP_METADATA = {
  name: 'HieroForge',
  description: 'Concentrated liquidity AMM on Hedera',
  icons: ['https://vitejs.dev/logo.svg'],
  url: typeof window !== 'undefined' ? window.location.origin : '',
}

function formatAccountId(accountId) {
  if (!accountId) return ''
  const s = String(accountId)
  if (s.length <= 12) return s
  return `${s.slice(0, 8)}...${s.slice(-4)}`
}

export function HashPackProvider({ children }) {
  const [accountId, setAccountId] = useState(null)
  const [isInitialized, setIsInitialized] = useState(false)
  const [isConnecting, setIsConnecting] = useState(false)
  const [error, setError] = useState(null)
  const hashConnectRef = useRef(null)

  const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID
  const network = import.meta.env.VITE_HEDERA_NETWORK || 'testnet'

  useEffect(() => {
    if (!projectId || projectId === 'your_project_id_here') {
      setError('Missing VITE_WALLETCONNECT_PROJECT_ID. Add it to .env (see .env.example).')
      return
    }

    let hashconnect = null

    const ledgerId =
      network === 'mainnet'
        ? LedgerId.MAINNET
        : network === 'previewnet'
          ? LedgerId.PREVIEWNET
          : LedgerId.TESTNET

    hashconnect = new HashConnect(ledgerId, projectId, APP_METADATA, false)

    hashconnect.pairingEvent.on((pairingData) => {
      const id = pairingData?.accountIds?.[0] ?? null
      setAccountId(id)
      setIsConnecting(false)
      setError(null)
      try {
        ModalCtrl.close()
      } catch (_) {
        // ignore if modal state not available
      }
    })

    hashconnect.disconnectionEvent.on(() => {
      setAccountId(null)
    })

    hashconnect
      .init()
      .then(() => {
        hashConnectRef.current = hashconnect
        setIsInitialized(true)
        setError(null)
        if (hashconnect.connectedAccountIds?.length > 0) {
          setAccountId(hashconnect.connectedAccountIds[0].toString())
        }
      })
      .catch((err) => {
        setError(err?.message ?? 'Failed to initialize HashPack')
        setIsInitialized(false)
      })

    return () => {
      hashConnectRef.current = null
    }
  }, [projectId, network])

  const connect = useCallback(async () => {
    if (!isInitialized) {
      setError('Wallet not ready. Wait for init or check .env')
      return
    }
    const hc = hashConnectRef.current
    if (!hc) {
      setError('HashPack not loaded')
      return
    }
    setError(null)
    setIsConnecting(true)
    try {
      await hc.openPairingModal()
    } catch (err) {
      setError(err?.message ?? 'Failed to open HashPack')
      setIsConnecting(false)
    }
  }, [isInitialized])

  const disconnect = useCallback(async () => {
    const hc = hashConnectRef.current
    if (hc) {
      try {
        await hc.disconnect()
      } catch (_) {
        setAccountId(null)
      }
    } else {
      setAccountId(null)
    }
    setIsConnecting(false)
  }, [])

  const value = {
    accountId,
    formattedAccountId: formatAccountId(accountId),
    isConnected: !!accountId,
    isInitialized,
    isConnecting,
    error,
    connect,
    disconnect,
    hashConnectRef,
  }

  return (
    <HashPackContext.Provider value={value}>
      {children}
    </HashPackContext.Provider>
  )
}

export function useHashPack() {
  const ctx = useContext(HashPackContext)
  if (!ctx) throw new Error('useHashPack must be used within HashPackProvider')
  return ctx
}
