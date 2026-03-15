import type { NextConfig } from 'next'
import path from 'path'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)

/**
 * Webpack plugin that fixes duplicate variable declarations produced by the
 * SWC minifier when scope-hoisting large ESM barrels (e.g. @hashgraph/sdk).
 *
 * The SWC bug generates patterns like `let n,n;` at module scope, which is
 * a SyntaxError at runtime.  This plugin renames the duplicate to a fresh
 * identifier so the chunk is valid JS.
 */
class FixDuplicateLetPlugin {
  apply(compiler: any) {
    compiler.hooks.compilation.tap('FixDuplicateLetPlugin', (compilation: any) => {
      compilation.hooks.processAssets.tap(
        {
          name: 'FixDuplicateLetPlugin',
          stage: compiler.webpack.Compilation.PROCESS_ASSETS_STAGE_OPTIMIZE_INLINE ?? 700,
        },
        (assets: Record<string, any>) => {
          for (const [name, asset] of Object.entries(assets)) {
            if (!name.endsWith('.js')) continue
            const source = asset.source()
            if (typeof source !== 'string') continue

            // Fix "let n,n;" → "let n,n$1;"  (and similar patterns)
            const fixed = source.replace(
              /\blet\s+([a-zA-Z_$][\w$]*)\s*,\s*\1\s*[;,]/g,
              (match: string, varName: string) => {
                const suffix = match.endsWith(',') ? ',' : ';'
                return `let ${varName},${varName}$1${suffix}`
              },
            )

            if (fixed !== source) {
              compilation.updateAsset(
                name,
                new compiler.webpack.sources.RawSource(fixed),
              )
            }
          }
        },
      )
    })
  }
}

const nextConfig: NextConfig = {
  reactStrictMode: true,
  webpack(config, { isServer }) {
    config.resolve = config.resolve ?? {}

    const sdkRoot = path.dirname(require.resolve('@hashgraph/sdk/package.json'))

    // hashconnect imports '@hashgraph/proto' (the old package name).
    // In SDK >=2.80 this was renamed to '@hiero-ledger/proto' and lives
    // inside the SDK's own node_modules.
    const protoPath = path.join(sdkRoot, 'node_modules', '@hiero-ledger', 'proto')
    config.resolve.alias = {
      ...config.resolve.alias,
      '@hashgraph/proto': protoPath,
    }

    if (!isServer) {
      config.resolve.alias = {
        ...config.resolve.alias,
        '@hashgraph/sdk': path.join(sdkRoot, 'lib', 'browser.js'),
      }
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
        http2: false,
        dns: false,
        child_process: false,
      }

      // Fix SWC minifier bug that generates "let n,n;" in scope-hoisted chunks
      config.plugins = config.plugins ?? []
      config.plugins.push(new FixDuplicateLetPlugin())
    }

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
