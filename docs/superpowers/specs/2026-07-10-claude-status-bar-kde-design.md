# Claude Status Bar for KDE — Design Spec

**Date:** 2026-07-10
**Status:** Approved for planning
**Target:** KDE Plasma 6 (verified: Plasma 6.7.2, Qt6/KF6)

## 1. Purpose

A KDE Plasma port of [claude-status-bar](https://github.com/m1ckc3s/claude-status-bar)
(a macOS menu bar app). It shows Claude Code's real-time activity in the Plasma
panel, and — on click — the account's subscription usage limits (5-hour and
weekly/72h windows).

Two independent capabilities:

1. **Live activity indicator** — panel icon reflecting what Claude Code is doing
   right now, aggregated across all concurrent sessions.
2. **Usage limits popup** — on click, show the account's 5-hour and weekly
   utilization from Anthropic's OAuth usage endpoint.

## 2. Scope

### In scope (MVP)
- Four core activity states: `thinking`, `tool` (with tool label), `waiting`
  (needs permission/input), `idle`.
- Multi-session aggregation with priority `waiting > tool > thinking > idle`.
- Elapsed timer while active.
- Popup listing active sessions (state, tool, cwd, elapsed).
- **Panel usage readout (right-aligned):** live 5-hour % and weekly (~72h) %
  utilization shown directly in the compact panel representation, e.g.
  `5h 42% · 7d 18%`, fed by a low-frequency background poll.
- **Config toggle** to show/hide that panel usage readout (default: shown).
  Hiding it also stops the background poll (usage then loads only when the popup
  opens), reducing API calls.
- Popup usage section: the same two windows shown larger as progress bars with
  reset hints.
- Auto-install script that merges hooks into `~/.claude/settings.json` and
  installs the plasmoid.

### Out of scope (deferred)
- Decorative options (rotating thinking verbs, animation styles, icon color
  choices, timer toggle).
- Local token/cost usage from `stats-cache.json`/transcripts — the user chose to
  show **only** the subscription limit windows.
- Packaging for the KDE Store, signing, distro packages.

## 3. Chosen approaches (decided during brainstorming)

- **Form factor:** native Plasma widget (**plasmoid**, QML/KF6). Not a
  standalone tray app.
- **Status transport:** per-session status files + a polling aggregator
  (approach A). Each session writes only its own file → no write races, no
  daemon.
- **Hook install:** an automatic `install.sh` that merges into existing
  `settings.json` hook groups (the user already runs many hooks; we must append,
  never overwrite).
- **Usage:** subscription limit windows **only**, fetched live from the OAuth
  endpoint. No local-stats fallback.

## 4. Architecture

```
Claude Code (N concurrent sessions)
   │  hook events (configured in ~/.claude/settings.json)
   ▼
claude-status-hook.py  ──writes──►  <data>/sessions/<session_id>.json
                                            │
        claude-status-aggregate.py (reads all, merges, prints 1 JSON line)
                                            ▲  polled every ~1s
                                            │
                                    ┌───────┴──────────────────────────┐
                                    │           PLASMOID (QML)          │
   usage-fetch.py ◄──poll ~5min─────┤  compact: icon+timer+label |usage%│
   (GET /api/oauth/usage, cached)   │  full: sessions + usage bars      │
                                    └───────────────────────────────────┘
```

**Data directory:** `${XDG_DATA_HOME:-~/.local/share}/claude-status-bar/`
- `bin/` — the three scripts (installed copies).
- `sessions/<session_id>.json` — per-session status.
- `usage-cache.json` — last usage-endpoint response + fetch timestamp.

## 5. Components

### 5.1 Hook script — `claude-status-hook.py`
One Python script, dispatched by the event name passed as `argv[1]`. Reads the
Claude Code hook payload (JSON) from stdin; writes/updates
`sessions/<session_id>.json`.

Event → action:

| Event | Action |
|-------|--------|
| `SessionStart` | create file, `state=idle` |
| `UserPromptSubmit` | `state=thinking`; set `started_at=now` if not already set |
| `PreToolUse` | `state=tool`, `tool=<tool_name from payload>` |
| `PostToolUse`, `PostToolUseFailure` | `state=thinking` |
| `Notification` | `state=waiting` |
| `Stop` | `state=idle`; clear `started_at` |
| `SessionEnd` | delete the session file |

Every write also sets `updated_at=now`, `cwd`, `session_id`. Writes are atomic
(write temp file in the same dir, `os.replace`). The script must be fast and must
never block or error Claude Code — wrap the body in a broad try/except that exits
0 regardless. Python is used (guaranteed present) for reliable stdin JSON parsing.

**Session file schema:**
```json
{
  "session_id": "…",
  "state": "thinking|tool|waiting|idle",
  "tool": "Edit",
  "started_at": 1720000000,
  "updated_at": 1720000005,
  "cwd": "/home/user/project"
}
```

### 5.2 Aggregator — `claude-status-aggregate.py`
Run by the plasmoid on a ~1s interval. Reads every `sessions/*.json`:
- Drop **stale** files: `state != idle` and `now - updated_at > STALE_SECS`
  (default 900s) — guards against sessions that died without firing `Stop`/
  `SessionEnd`.
- Aggregate by priority `waiting > tool > thinking > idle`:
  - `waiting`: state=waiting; `waiting_count`.
  - else `tool`: state=tool; `tool` = tool of the most-recently-updated tool
    session; `active_count`.
  - else `thinking`: state=thinking; `active_count`.
  - else idle.
- `started_at` = **earliest** `started_at` among active (non-idle) sessions, so
  the panel timer reflects the longest-running work.
- Emit one JSON line:
```json
{ "state":"tool", "tool":"Edit", "started_at":1720000000,
  "active_count":2, "waiting_count":0, "sessions":[ {…per-session…} ] }
```
`sessions` (the trimmed per-session list) feeds the popup so the plasmoid needs
only this one call.

### 5.3 Usage fetcher — `usage-fetch.py`
The script itself just fetches + caches; *when* it runs depends on the
`showUsageOnPanel` config toggle (§5.5):
- **Toggle on (default):** the plasmoid runs it on a **background timer** at
  `USAGE_POLL_INTERVAL` (default 300s / 5 min) via a second executable
  `DataSource`, so the panel readout stays live.
- **Toggle off:** no background poll; the script runs only when the popup opens
  (gated by the freshness check below).

In both cases a fetch is gated by the `usage-cache.json` freshness check (skip if
cache newer than `USAGE_MIN_INTERVAL`, default 300s) so a popup click never adds
an extra call on top of a background poll. 5 min is well within the endpoint's
tolerance **provided the `User-Agent: claude-code/<ver>` header is sent**; this is
the single most important rate-limit mitigation.

- Read `accessToken`, `expiresAt` from `~/.claude/.credentials.json`
  (`claudeAiOauth`).
- If `now >= expiresAt`: emit `{ "status":"reauth" }` (do not attempt refresh in
  MVP; just surface it).
- `GET https://api.anthropic.com/api/oauth/usage` with headers:
  - `Authorization: Bearer <accessToken>`
  - `User-Agent: claude-code/<version>` — **required**; missing UA → aggressive
    429 bucket. Derive `<version>` from `claude --version` at install time, baked
    into the script (fallback to a recent constant).
- On success: write `usage-cache.json` = `{ "status":"ok", "fetched_at":now,
  "five_hour":{…}, "seven_day":{…} }` (store the raw `utilization` and any
  `resets_at` fields the endpoint returns) and print it.
- On `429`: print `{ "status":"rate_limited", …last cache… }` and do **not**
  overwrite the cache timestamp forward (respect backoff).
- On `401`: print `{ "status":"reauth" }`.
- On network/other error: print `{ "status":"error", …last cache if any… }`.

Uses only the Python stdlib (`urllib.request`) — no extra deps.

### 5.4 Plasmoid (QML, Plasma 6 / KF6)
Package id e.g. `org.kde.claudestatusbar`. Standard layout:
```
package/
  metadata.json                (Plasma 6 plasmoid metadata, KPackage)
  contents/ui/main.qml         (PlasmoidItem root)
  contents/ui/CompactView.qml  (panel representation)
  contents/ui/FullView.qml     (popup)
  contents/ui/UsageBars.qml    (5h/weekly bars)
  contents/ui/configGeneral.qml(settings page)
  contents/config/main.xml     (config keys)
  contents/config/config.qml   (registers settings page)
  contents/icons/…             (Claude logo states)
```

- **Data sources:** two `Plasma5Support.DataSource { engine: "executable" }`
  instances — (a) `claude-status-aggregate.py` on a 1000ms interval for activity;
  (b) `usage-fetch.py` on a `USAGE_POLL_INTERVAL` (default 300000ms) interval for
  usage. Each parses its JSON line into a state object.
- **Compact representation** (in panel): a `RowLayout`.
  - **Left/main:** Claude icon whose appearance follows `state` (idle =
    monochrome logo; thinking/tool = highlighted; waiting = yellow dot overlay),
    a short tool label ("Editing", "Running", …) mapped from tool name, and the
    elapsed timer text driven by a local QML `Timer` ticking every 1s computing
    `now - started_at` (smooth regardless of aggregator cadence).
  - **Right (right-aligned, after a spacer):** shown only when
    `showUsageOnPanel` is true — the usage readout
    `5h {five_hour}% · 7d {seven_day}%` from `usage-cache`. Colour-graded
    (e.g. neutral <70%, amber 70–90%, red >90%). While `status` is
    `rate_limited`/`error`/`reauth` or before the first successful fetch, show the
    last known values dimmed, or `5h —% · 7d —%` if none yet. On very narrow
    panels the label collapses to just the percentages (icon+% always kept).
- **Full representation** (popup on click):
  - Session list: per session show state, tool, `cwd` basename, elapsed.
  - Usage section (`UsageBars.qml`): two progress bars — **5-hour** and
    **weekly (~72h)** — from `five_hour.utilization` / `seven_day.utilization`,
    a reset-time hint if provided, and a "cập nhật lúc HH:MM" line. States
    `rate_limited` / `reauth` / `error` render an inline message instead of stale
    100%-looking bars.
  - The popup reads the same `usage-cache`; it does not force an extra fetch
    beyond the min-interval gate, since the background poll already keeps the
    cache fresh.

**Tool-name → label map** (extensible): `Edit/Write/MultiEdit → "Editing"`,
`Bash → "Running"`, `Read → "Reading"`, `Grep/Glob → "Searching"`,
`WebFetch/WebSearch → "Browsing"`, `Task → "Delegating"`, default → the raw name.

### 5.5 Plasmoid configuration
Standard plasmoid config: `contents/config/main.xml` declares config keys;
`contents/ui/configGeneral.qml` provides the settings page; `config.qml`
registers it. The config UI opens via the widget's right-click "Configure…".

MVP config keys:

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `showUsageOnPanel` | bool | `true` | Show/hide the right-aligned `5h % · 7d %` readout in the compact panel view. When false, the background usage `DataSource` interval is disabled (set to 0) so usage is fetched only on popup open. |

The compact view binds the usage readout's `visible` and the usage
`DataSource`'s polling `interval` to `plasmoid.configuration.showUsageOnPanel`,
so toggling takes effect live without restart. Additional keys (poll interval,
colour thresholds) are out of scope for MVP but the config file is the place they
would go.

### 5.6 Installer — `install.sh` (+ `uninstall.sh`)
`install.sh`:
1. Copy the three scripts to `<data>/bin/`, `chmod +x`.
2. Bake the detected `claude --version` into `usage-fetch.py` (or a sibling
   config) for the UA header.
3. **Merge** hooks into `~/.claude/settings.json` using Python:
   - Backup to `settings.json.bak.<epoch>` first.
   - For each event above, append a hook entry pointing at
     `<data>/bin/claude-status-hook.py <EventName>` to the existing matcher group
     (create the group/array if absent). Skip if an identical entry already
     exists (idempotent re-runs).
4. Install the plasmoid: `kpackagetool6 --type Plasma/Applet --install package/`
   (upgrade with `--upgrade` on re-run), fallback to copying into
   `~/.local/share/plasma/plasmoids/`.
5. Print next steps: add the widget to a panel; if needed
   `kquitapp6 plasmashell && kstart plasmashell` (or log out/in).

`uninstall.sh`: remove the plasmoid, strip our hook entries from `settings.json`
(again via Python, matching our command path), leave the data dir removal opt-in.

## 6. Data flow (end to end)

1. User submits a prompt → `UserPromptSubmit` hook → session file
   `state=thinking, started_at`.
2. Claude runs a tool → `PreToolUse` → `state=tool, tool=…`; done → `PostToolUse`
   → `state=thinking`.
3. Permission needed → `Notification` → `state=waiting`.
4. Turn ends → `Stop` → `state=idle`.
5. Plasmoid polls aggregator every 1s → updates panel icon/label/timer.
6. If `showUsageOnPanel` is on, plasmoid polls `usage-fetch.py` every ~5 min →
   updates the right-aligned `5h % · 7d %` readout on the panel from
   `usage-cache`. If off, no background poll and no panel readout.
7. User clicks panel icon → popup opens → renders sessions from the last
   aggregate + the same cached usage as larger bars (no extra fetch unless the
   cache is past the min-interval gate).

## 7. Error handling & edge cases

- **Hook robustness:** hook never fails Claude Code — broad try/except, exit 0,
  atomic writes.
- **Dead sessions:** staleness sweep in the aggregator (900s) + `SessionEnd`
  cleanup.
- **Concurrent sessions:** isolated per-session files → no write races.
- **Usage rate limiting (429):** the documented, aggressive failure mode, and the
  main risk of a continuous panel readout. Mitigations: mandatory
  `User-Agent: claude-code/<ver>` header; background poll no faster than ~5 min
  (`USAGE_POLL_INTERVAL`); popup reuses the cache (no extra call); on 429 keep
  showing the last cached % dimmed and respect backoff (do not advance the cache
  timestamp forward). Never poll on the 1s activity cadence.
- **Token expiry / 401:** surface "cần đăng nhập lại"; no silent refresh in MVP.
- **Endpoint schema drift:** isolated to `usage-fetch.py`; failure degrades the
  usage section only, never the activity indicator.

## 8. Risk & Spike (Step 0 of the plan)

The entire usage feature depends on an **undocumented** OAuth endpoint
(`/api/oauth/usage`) that is known to rate-limit aggressively. Cf. the user's
prior `claude-gateway` OAuth spike that was never validated.

**Spike (do first, before any usage UI):** a minimal script reads the local
access token, sends `GET /api/oauth/usage` with the `claude-code/<ver>` UA
header, and prints the raw JSON. Confirm:
- 200 with `five_hour.utilization` and `seven_day.utilization` present.
- Whether reset timestamps are included.
- Behaviour without/with the UA header (rate-limit sensitivity).

**Gate:** if the spike fails (persistent 429, different schema, or auth we can't
satisfy), STOP and report back — the activity indicator ships independently, but
the usage section does not, and the user is consulted before building around a
broken dependency.

## 9. Testing strategy

- **Hook script:** pipe representative payloads for each event to
  `claude-status-hook.py <Event>`; assert the resulting session file contents
  (state, tool, started_at set/cleared) and atomic-write behaviour; assert exit 0
  on malformed input.
- **Aggregator:** create fixture `sessions/*.json` sets and assert the emitted
  JSON for: single-session each state; priority ordering
  (waiting>tool>thinking>idle); earliest `started_at`; staleness dropping.
- **Usage fetcher:** unit-test response handling with a stubbed HTTP layer for
  200 / 429 / 401 / network-error → assert the emitted `status` and cache
  behaviour. (No live calls in the test suite; the live check is the Step-0
  spike.)
- **Plasmoid QML:** manual verification against a mock aggregator that cycles
  states, plus a mock usage payload; no automated QML UI tests in MVP.

## 10. Deliverables

```
claude-status-bar-kde/
  scripts/claude-status-hook.py
  scripts/claude-status-aggregate.py
  scripts/usage-fetch.py
  scripts/spike-usage.py          (Step-0 feasibility)
  package/                        (plasmoid)
  install.sh
  uninstall.sh
  tests/
  README.md
```
