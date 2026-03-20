import type { Metadata } from "next";
import Providers from "./Providers";
import "@/styles/globals.css";

export const metadata: Metadata = {
  title: "HieroForge",
  description: "Concentrated liquidity AMM on Hedera",
  icons: {
    icon: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
