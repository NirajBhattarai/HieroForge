import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { HashPackProvider } from './context/HashPackContext.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <HashPackProvider>
      <App />
    </HashPackProvider>
  </StrictMode>,
)
