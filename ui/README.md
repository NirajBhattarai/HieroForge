# HieroForge UI

Frontend for **HieroForge** (concentrated liquidity AMM on Hedera). Built with React + Vite.

- **Contracts / ABIs:** `../hieroforge-core/out/`
- **Run dev:** `npm run dev`
- **Build:** `npm run build`

### HashPack wallet

1. Copy `.env.example` to `.env`.
2. Get a WalletConnect project ID from [cloud.walletconnect.com](https://cloud.walletconnect.com/) and set `VITE_WALLETCONNECT_PROJECT_ID`.
3. Optionally set `VITE_HEDERA_NETWORK` to `testnet`, `mainnet`, or `previewnet` (default: testnet).
4. Install [HashPack](https://www.hashpack.app/) browser extension, then click **Connect HashPack** in the app.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Babel](https://babeljs.io/) (or [oxc](https://oxc.rs) when used in [rolldown-vite](https://vite.dev/guide/rolldown)) for Fast Refresh
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/) for Fast Refresh

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend using TypeScript with type-aware lint rules enabled. Check out the [TS template](https://github.com/vitejs/vite/tree/main/packages/create-vite/template-react-ts) for information on how to integrate TypeScript and [`typescript-eslint`](https://typescript-eslint.io) in your project.
