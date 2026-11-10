#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required only to fetch the parser source at build time." >&2
  echo "Install it with: sudo apt install npm" >&2
  exit 1
fi

npm install --ignore-scripts --no-audit --no-fund
mkdir -p resources
install -m 0644 node_modules/markdown-it/dist/markdown-it.min.js resources/markdown-it.min.js

printf 'Bundled markdown-it %s into resources/markdown-it.min.js\n' \
  "$(node -p "require('./node_modules/markdown-it/package.json').version")"
