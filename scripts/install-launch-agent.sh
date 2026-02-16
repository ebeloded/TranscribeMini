#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_TEMPLATE="$REPO_ROOT/launchd/com.transcribemini.agent.plist"
TARGET_PLIST="$HOME/Library/LaunchAgents/com.transcribemini.agent.plist"
LOG_DIR="$HOME/Library/Logs/TranscribeMini"
STDOUT_LOG="$LOG_DIR/launchd.out.log"
STDERR_LOG="$LOG_DIR/launchd.err.log"

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

if [ ! -x "$REPO_ROOT/.build/debug/TranscribeMini" ]; then
  echo "Building TranscribeMini..."
  (cd "$REPO_ROOT" && swift build)
fi

EXECUTABLE_PATH="$REPO_ROOT/.build/debug/TranscribeMini"

if [ ! -x "$EXECUTABLE_PATH" ]; then
  echo "Error: executable not found at $EXECUTABLE_PATH"
  exit 1
fi

sed \
  -e "s|__EXECUTABLE__|$EXECUTABLE_PATH|g" \
  -e "s|__STDOUT__|$STDOUT_LOG|g" \
  -e "s|__STDERR__|$STDERR_LOG|g" \
  "$PLIST_TEMPLATE" > "$TARGET_PLIST"

# If already loaded, unload first so updates are picked up.
launchctl bootout "gui/$(id -u)/com.transcribemini.agent" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$TARGET_PLIST"
launchctl enable "gui/$(id -u)/com.transcribemini.agent"
launchctl kickstart -k "gui/$(id -u)/com.transcribemini.agent"

echo "Installed and started: com.transcribemini.agent"
echo "Plist: $TARGET_PLIST"
echo "Executable: $EXECUTABLE_PATH"
echo "Logs: $STDOUT_LOG and $STDERR_LOG"
