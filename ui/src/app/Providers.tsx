'use client'

import { useEffect, useState, type ReactNode } from 'react'

export default function Providers({ children }: { children: ReactNode }) {
  const [Provider, setProvider] = useState<React.ComponentType<{ children: ReactNode }> | null>(null)

  useEffect(() => {
    import('@/context/HashPackContext').then((mod) => {
      setProvider(() => mod.HashPackProvider)
    })
  }, [])

  if (!Provider) return <>{children}</>
  return <Provider>{children}</Provider>
}
