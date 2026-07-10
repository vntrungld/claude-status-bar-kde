---
name: reload-plasmoid
description: Use when you need to see QML/plasmoid changes live in the panel — reinstalls the package and restarts plasmashell so edits under package/ take effect.
disable-model-invocation: true
---

# Reload Plasmoid

## Overview

Plasma caches the installed applet, so edits under `package/` do not appear until
the package is re-registered and plasmashell is restarted. This skill does both.

## Steps

1. Upgrade the installed package from the working tree (install if not yet present):

   ```bash
   kpackagetool6 --type Plasma/Applet --upgrade ./package/ \
     || kpackagetool6 --type Plasma/Applet --install ./package/
   ```

2. Restart the shell so the new QML loads:

   ```bash
   kquitapp6 plasmashell && kstart plasmashell
   ```

3. Confirm the widget is still on the panel. If it vanished, re-add **Claude Status
   Bar** from the widget list.

## Notes

- Only `package/` is registered by `kpackagetool6`; the Python backend lives in
  `$XDG_DATA_HOME/claude-status-bar/bin` and is updated by `./install.sh`, not by
  this skill. Re-run `./install.sh` if you changed anything under `scripts/`.
- `kstart plasmashell` returns immediately; give the shell a second to repaint.
- Bumping `Version` in `package/metadata.json` avoids `--upgrade` no-op'ing when
  the version is unchanged.
