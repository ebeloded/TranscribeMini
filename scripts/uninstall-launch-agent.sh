#!/usr/bin/env bash
set -euo pipefail

TARGET_PLIST="$HOME/Library/LaunchAgents/com.transcribemini.agent.plist"

launchctl bootout "gui/$(id -u)/com.transcribemini.agent" >/dev/null 2>&1 || true
rm -f "$TARGET_PLIST"

echo "Uninstalled: com.transcribemini.agent"
