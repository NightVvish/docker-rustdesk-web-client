#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-5000}"
APP_DIR=/app/build/web
SCRIPT_DIR=/app/server

echo "Preparing RustDesk Web configuration on port $PORT…"
cd "$APP_DIR"

python3 "$SCRIPT_DIR/generate_env_config.py" "$APP_DIR/env-config.js"

if ! grep -Fq 'src="env-config.js"' index.html; then
  sed -i 's|</head>|  <script src="env-config.js"></script>\n</head>|' index.html
fi

echo "Server starting on port $PORT…"
exec python3 -m http.server --bind 0.0.0.0 "$PORT"
