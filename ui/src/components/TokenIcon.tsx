import { useState } from "react";
import { TOKEN_IMAGES } from "../constants";

interface TokenIconProps {
  symbol: string;
  size?: number;
  className?: string;
}

// Generate a consistent gradient based on a string hash
function symbolToGradient(symbol: string): string {
  let hash = 0;
  for (let i = 0; i < symbol.length; i++) {
    hash = symbol.charCodeAt(i) + ((hash << 5) - hash);
  }
  const h1 = Math.abs(hash % 360);
  const h2 = (h1 + 40) % 360;
  return `linear-gradient(135deg, hsl(${h1}, 70%, 45%) 0%, hsl(${h2}, 60%, 55%) 100%)`;
}

/** Token logo: image if TOKEN_IMAGES[symbol] exists, else gradient circle with initial. */
export function TokenIcon({
  symbol,
  size = 28,
  className = "",
}: TokenIconProps) {
  const src = TOKEN_IMAGES[symbol];
  const [imgFailed, setImgFailed] = useState(false);
  const letter = symbol.slice(0, 1).toUpperCase();
  const showImg = src && !imgFailed;

  if (showImg) {
    return (
      <img
        src={src}
        alt={symbol}
        className={`shrink-0 rounded-full object-cover ${className}`}
        style={{ width: size, height: size }}
        onError={() => setImgFailed(true)}
      />
    );
  }

  return (
    <div
      className={`shrink-0 rounded-full flex items-center justify-center font-bold text-white ${className}`}
      style={{
        width: size,
        height: size,
        background: symbolToGradient(symbol),
        fontSize: Math.round(size * 0.42),
      }}
      title={symbol}
    >
      {letter}
    </div>
  );
}

/** Overlapping dual token icons (Uniswap-style pair display). */
export function TokenPairIcon({
  symbol0,
  symbol1,
  size = 28,
  className = "",
}: {
  symbol0: string;
  symbol1: string;
  size?: number;
  className?: string;
}) {
  return (
    <div
      className={`flex items-center ${className}`}
      style={{ width: size * 1.65 }}
    >
      <TokenIcon symbol={symbol0} size={size} />
      <div className="-ml-2 ring-2 ring-surface-1 rounded-full">
        <TokenIcon symbol={symbol1} size={size} />
      </div>
    </div>
  );
}
