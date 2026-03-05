#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="TranscribeMini"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.transcribemini.app}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
INFO_TEMPLATE="$REPO_ROOT/packaging/macos/Info.plist.template"

if [[ ! -f "$INFO_TEMPLATE" ]]; then
  echo "Missing Info.plist template: $INFO_TEMPLATE" >&2
  exit 1
fi

if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="0.1.0"
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
fi

echo "Building Swift package ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --package-path "$REPO_ROOT")"
EXECUTABLE="$BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Executable not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
else
  echo "Warning: resource bundle not found at $RESOURCE_BUNDLE"
fi

sed \
  -e "s|__BUNDLE_ID__|$APP_BUNDLE_ID|g" \
  -e "s|__VERSION__|$APP_VERSION|g" \
  -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
  "$INFO_TEMPLATE" > "$APP_DIR/Contents/Info.plist"

# The app uses a menu bar UI only; keep startup clean without Dock presence.
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "Built app bundle: $APP_DIR"
