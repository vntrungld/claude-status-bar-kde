#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar"
BIN="$DATA/bin"
SETTINGS="$HOME/.claude/settings.json"

echo "Removing plasmoid"
kpackagetool6 --type Plasma/Applet --remove org.kde.claudestatusbar || true

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  python3 "$HERE/scripts/apply_settings_unmerge.py" "$SETTINGS" "$BIN"
fi
echo "Left data dir in place: $DATA (remove manually if desired)."
