#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/test.env" <<'EOF'
WEB_PORT=8080
BACKEND_HOST=rd.example.com
PROTO=https
RUSTDESK_TAG=enable-wss
EOF

output="$(ENV_FILE="$TEMP_DIR/test.env" "$ROOT_DIR/build.sh" config)"
grep -Fq 'Port web            : 8080 -> 80' <<<"$output"
grep -Fq 'Backend RustDesk    : rd.example.com' <<<"$output"
grep -Fq 'Protocole backend   : https' <<<"$output"
grep -Fq 'Référence source    : enable-wss' <<<"$output"

output="$(WEB_PORT=9090 ENV_FILE="$TEMP_DIR/test.env" "$ROOT_DIR/build.sh" config)"
grep -Fq 'Port web            : 9090 -> 80' <<<"$output"

if "$ROOT_DIR/build.sh" config argument-inattendu >/dev/null 2>&1; then
    echo "Un argument surnuméraire a été accepté" >&2
    exit 1
fi
