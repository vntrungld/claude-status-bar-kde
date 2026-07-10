#!/usr/bin/env bash
set -euo pipefail
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar"
BIN="$DATA/bin"
SETTINGS="$HOME/.claude/settings.json"

echo "Removing plasmoid"
kpackagetool6 --type Plasma/Applet --remove org.kde.claudestatusbar || true

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  python3 - "$SETTINGS" "$BIN" <<'PY'
import json, sys
sp, bin_dir = sys.argv[1], sys.argv[2]
s = json.load(open(sp))
needle = f"{bin_dir}/claude-status-hook.py"
for ev, groups in list(s.get("hooks", {}).items()):
    s["hooks"][ev] = [g for g in groups
                      if not any(needle in h.get("command", "") for h in g.get("hooks", []))]
    if not s["hooks"][ev]:
        del s["hooks"][ev]
json.dump(s, open(sp, "w"), indent=2)
print("Stripped status-bar hooks from", sp)
PY
fi
echo "Left data dir in place: $DATA (remove manually if desired)."
