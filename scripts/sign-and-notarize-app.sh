#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="TranscribeMini"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
APP_PATH="${APP_PATH:-$OUTPUT_DIR/$APP_NAME.app}"
ZIP_PATH="${ZIP_PATH:-$OUTPUT_DIR/$APP_NAME.zip}"
CERT_NAME="${CERT_NAME:-Developer ID Application}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle missing at $APP_PATH"
  echo "Run scripts/build-app-bundle.sh first." >&2
  exit 1
fi

echo "Signing app with certificate containing: $CERT_NAME"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$CERT_NAME" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --wait --keychain-profile "$NOTARY_KEYCHAIN_PROFILE"
else
  if [[ -z "$APPLE_ID" || -z "$APPLE_APP_PASSWORD" || -z "$APPLE_TEAM_ID" ]]; then
    echo "Notarization credentials missing. Provide either:"
    echo "  1) NOTARY_KEYCHAIN_PROFILE"
    echo "  2) APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID" >&2
    exit 1
  fi
  xcrun notarytool submit "$ZIP_PATH" --wait \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID"
fi

xcrun stapler staple "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "Notarized artifact: $ZIP_PATH"
echo "SHA256: $SHA256"
