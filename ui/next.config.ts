import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['hashconnect', '@hashgraph/sdk'],
  webpack(config) {
    // Suppress "Critical dependency" warnings from hashconnect / hedera-wallet-connect
    config.ignoreWarnings = [
      ...(config.ignoreWarnings ?? []),
      { module: /node_modules[\\/]@hashgraph[\\/]hedera-wallet-connect/ },
      { module: /node_modules[\\/]hashconnect/ },
    ]
    return config
  },
}

export default nextConfig
