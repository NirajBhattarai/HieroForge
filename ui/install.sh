#!/bin/sh
# Load nvm if available, then run npm install (fixes "command not found: npm" in some terminals)
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  . "$HOME/.nvm/nvm.sh"
  nvm use 2>/dev/null || nvm install --lts 2>/dev/null || true
fi
if command -v npm >/dev/null 2>&1; then
  npm install
else
  echo "npm not found. Install Node.js (e.g. from https://nodejs.org or: brew install node) and try again."
  exit 1
fi
