import { createContext, useContext, useState, useEffect, useCallback, useRef, type ReactNode } from 'react'
import { HashConnect } from 'hashconnect'
import { LedgerId } from '@hashgraph/sdk'
import { ModalCtrl } from '@walletconnect/modal-core'

export interface HashPackContextValue {
  accountId: string | null
  formattedAccountId: string
  isConnected: boolean
  isInitialized: boolean
  isConnecting: boolean
  error: string | null
  connect: () => Promise<void>
  disconnect: () => Promise<void>
  hashConnectRef: React.MutableRefObject<HashConnect | null>
}

const HashPackContext = createContext<HashPackContextValue | null>(null)

const APP_METADATA = {
  name: 'HieroForge',
  description: 'Concentrated liquidity AMM on Hedera',
  icons: ['https://vitejs.dev/logo.svg'],
  url: typeof window !== 'undefined' ? window.location.origin : '',
}

function formatAccountId(accountId: string | null): string {
  if (!accountId) return ''
  const s = String(accountId)
  if (s.length <= 12) return s
  return `${s.slice(0, 8)}...${s.slice(-4)}`
}

interface PairingData {
  accountIds?: string[]
}

export function HashPackProvider({ children }: { children: ReactNode }) {
  const [accountId, setAccountId] = useState<string | null>(null)
  const [isInitialized, setIsInitialized] = useState(false)
  const [isConnecting, setIsConnecting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const hashConnectRef = useRef<HashConnect | null>(null)

  const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID
  const network = import.meta.env.VITE_HEDERA_NETWORK || 'testnet'

  useEffect(() => {
    if (!projectId || projectId === 'your_project_id_here') {
      setError('Missing VITE_WALLETCONNECT_PROJECT_ID. Add it to .env (see .env.example).')
      return
    }

    let hashconnect: HashConnect | null = null

    const ledgerId =
      network === 'mainnet'
        ? LedgerId.MAINNET
        : network === 'previewnet'
          ? LedgerId.PREVIEWNET
          : LedgerId.TESTNET

    hashconnect = new HashConnect(ledgerId, projectId, APP_METADATA, false)

    hashconnect.pairingEvent.on((pairingData: PairingData) => {
      const id = pairingData?.accountIds?.[0] ?? null
      setAccountId(id)
      setIsConnecting(false)
      setError(null)
      try {
        ModalCtrl.close()
      } catch {
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
        if ((hashconnect?.connectedAccountIds?.length ?? 0) > 0) {
          setAccountId(hashconnect.connectedAccountIds?.[0]?.toString() ?? null)
        }
      })
      .catch((err: unknown) => {
        setError(err instanceof Error ? err.message : 'Failed to initialize HashPack')
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
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to open HashPack')
      setIsConnecting(false)
    }
  }, [isInitialized])

  const disconnect = useCallback(async () => {
    const hc = hashConnectRef.current
    if (hc) {
      try {
        await hc.disconnect()
      } catch {
        setAccountId(null)
      }
    } else {
      setAccountId(null)
    }
    setIsConnecting(false)
  }, [])

  const value: HashPackContextValue = {
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

export function useHashPack(): HashPackContextValue {
  const ctx = useContext(HashPackContext)
  if (!ctx) throw new Error('useHashPack must be used within HashPackProvider')
  return ctx
}
