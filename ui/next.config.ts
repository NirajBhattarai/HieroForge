import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['hashconnect', '@hashgraph/sdk'],
}

export default nextConfig
