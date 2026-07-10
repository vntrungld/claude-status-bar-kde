# Claude Status Bar for KDE

A KDE Plasma 6 plasmoid showing Claude Code's live activity in the panel, with
the account's 5-hour and weekly usage percentages on the right.

## Requirements
- KDE Plasma 6 (Qt6/KF6)
- Python 3
- Claude Code CLI (logged in — usage reads the local OAuth token)

## Install
```bash
./install.sh
```
Then add the **Claude Status Bar** widget to a panel. Uninstall with `./uninstall.sh`.

## What it shows
- Panel: state glyph, tool label ("Editing"…), elapsed timer, and `5h N% · 7d N%`.
- Popup: per-session list + 5-hour / weekly usage bars.
- Right-click → Configure to hide the panel usage %.

## Usage data
Usage comes from Claude's `/api/oauth/usage` endpoint (same source as `/usage`),
polled at most every 5 minutes. It is undocumented and rate-limited; if it fails
the last known values are shown dimmed.
