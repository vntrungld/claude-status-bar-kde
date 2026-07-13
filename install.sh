#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar"
BIN="$DATA/bin"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing scripts to $BIN"
mkdir -p "$BIN"
cp "$HERE"/scripts/statusbar_paths.py "$HERE"/scripts/claude-status-hook.py \
   "$HERE"/scripts/claude-status-aggregate.py "$HERE"/scripts/usage-fetch.py \
   "$HERE"/scripts/cux-usage-fetch.py "$BIN/"
chmod +x "$BIN"/*.py

# Bake the current claude version into the UA header.
VER="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
[ -n "$VER" ] && sed -i "s#claude-code/[0-9.]*#claude-code/$VER#" "$BIN/usage-fetch.py"

echo "Merging hooks into $SETTINGS (backup first)"
if [ -f "$SETTINGS" ]; then cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"; fi
python3 "$HERE/scripts/apply_settings_merge.py" "$SETTINGS" "$BIN"

echo "Installing plasmoid"
kpackagetool6 --type Plasma/Applet --install "$HERE/package/" 2>/dev/null \
  || kpackagetool6 --type Plasma/Applet --upgrade "$HERE/package/"

echo "Done. Add the 'Claude Status Bar' widget to a panel."
echo "If it does not appear, run: kquitapp6 plasmashell && kstart plasmashell"
