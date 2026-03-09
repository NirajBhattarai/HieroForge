import { useState } from 'react'
import { TOKEN_IMAGES } from '../constants'

interface TokenIconProps {
  symbol: string
  size?: number
  className?: string
}

/** Token logo: image if TOKEN_IMAGES[symbol] exists, else circle with first letter. */
export function TokenIcon({ symbol, size = 28, className = '' }: TokenIconProps) {
  const src = TOKEN_IMAGES[symbol]
  const [imgFailed, setImgFailed] = useState(false)
  const letter = symbol.slice(0, 1).toUpperCase()
  const showImg = src && !imgFailed

  if (showImg) {
    return (
      <img
        src={src}
        alt={symbol}
        className={`token-icon token-icon--img ${className}`}
        style={{ width: size, height: size, borderRadius: '50%', objectFit: 'cover' }}
        onError={() => setImgFailed(true)}
      />
    )
  }

  return (
    <div
      className={`token-icon token-icon--letter ${className}`}
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: 'var(--accent-muted)',
        color: 'var(--accent)',
        fontSize: Math.round(size * 0.5),
        fontWeight: 700,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
      title={symbol}
    >
      {letter}
    </div>
  )
}
