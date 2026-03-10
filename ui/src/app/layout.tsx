import type { Metadata } from 'next'
import { HashPackProvider } from '@/context/HashPackContext'
import './globals.css'

export const metadata: Metadata = {
  title: 'HieroForge',
  description: 'Concentrated liquidity AMM on Hedera',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en">
      <body>
        <HashPackProvider>
          {children}
        </HashPackProvider>
      </body>
    </html>
  )
}
