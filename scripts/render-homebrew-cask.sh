#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="${TEMPLATE:-$REPO_ROOT/packaging/homebrew/Casks/transcribe-mini.rb.template}"
OUT="${OUT:-$REPO_ROOT/dist/transcribe-mini.rb}"
VERSION="${VERSION:-}"
SHA256="${SHA256:-}"
URL="${URL:-}"

if [[ -z "$VERSION" || -z "$SHA256" || -z "$URL" ]]; then
  echo "Usage: VERSION=1.2.3 SHA256=<sha256> URL=<release_url> scripts/render-homebrew-cask.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

sed \
  -e "s|__VERSION__|$VERSION|g" \
  -e "s|__SHA256__|$SHA256|g" \
  -e "s|__URL__|$URL|g" \
  "$TEMPLATE" > "$OUT"

echo "Wrote cask file: $OUT"
