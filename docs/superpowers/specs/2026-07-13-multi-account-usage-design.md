# Multi-Account Usage Display (cux) — Design

**Date:** 2026-07-13
**Status:** Approved, pending implementation plan

## Problem

The plasmoid fetches and displays Claude subscription usage for a **single
account** — it reads `~/.claude/.credentials.json` and calls the OAuth usage
API (`usage-fetch.py`). Users who run cux ("Run multiple Claude Code Pro/Max
accounts as one") to juggle multiple accounts can only see the active account's
usage, even though cux already tracks usage for all of them.

Goal: when cux is present, show per-account usage for every managed account in
the popup, while leaving the experience **completely unchanged** for users who
don't use cux.

## Constraints & Principles

- **cux is additive, never a dependency.** No cux → identical to today's widget,
  byte-for-byte.
- **Single source of truth in cux mode.** All accounts (including the active
  one) render from the cux cache so numbers never disagree between panel and
  popup.
- **Reuse, don't fork.** Fallback delegates to the existing `usage-fetch.py`
  logic instead of duplicating OAuth code; the popup reuses the existing
  `UsageBars` component per account.
- **The widget must not hang.** cux refresh runs as a subprocess with a hard
  timeout.

## Data Sources (cux)

cux stores, under `${XDG_DATA_HOME:-$HOME/.local/share}/cux/`:

- `state.json` — `activeSlot` plus `accounts` map: each has `slot`, `email`,
  `alias`, `orgUuid`.
- `runtime/usage-cache.json` — keyed by `orgUuid`, each value:
  `{ five_hour: {utilization, resets_at}, seven_day: {utilization, resets_at},
  polled_at }`.

The join key between the two is `orgUuid`. cux's cache only refreshes on session
events, so it can be very stale (observed 3 days) unless the plasmoid refreshes
it itself.

`cux usage refresh` re-polls every account (~1.1s for 2 accounts) and rewrites
`usage-cache.json`. It prints a decorative banner to stdout — ignored.

## Architecture

### New script: `cux-usage-fetch.py`

Becomes the single usage command `main.qml` invokes (replacing the direct call
to `usage-fetch.py`). Behavior:

1. **Detect cux.** Locate the `cux` binary by searching `PATH` plus
   `~/.local/bin` (Plasma's session PATH may be minimal), and confirm
   `state.json` exists.
2. **cux present:**
   - Run `cux usage refresh` via `subprocess` with a ~25s timeout; ignore
     stdout/failure (best-effort freshness).
   - Read `state.json` + `runtime/usage-cache.json`, join by `orgUuid`.
   - Emit multi-account output (below). If refresh failed but the cache is
     readable, still render the (stale) cache — `status: "ok"`.
3. **cux absent, or state/cache unreadable:** import today's `usage-fetch.py`
   as a module and run its logic; emit single-account output (`multi: false`).

### Output shape

Superset of today's shape, so `CompactView` and the non-cux path are unchanged:

```json
{
  "status": "ok",
  "fetched_at": 1752384000,
  "five_hour": { "utilization": 41, "resets_at": "..." },
  "seven_day": { "utilization": 14, "resets_at": "..." },
  "multi": true,
  "accounts": [
    { "slot": 2, "alias": "lam-duc...", "email": "vn.trungld@gmail.com",
      "active": true,  "five_hour": {...}, "seven_day": {...}, "polled_at": 1752384000 },
    { "slot": 1, "alias": "oe", "email": "oedevai2@gmail.com",
      "active": false, "five_hour": {...}, "seven_day": {...}, "polled_at": 1752384000 }
  ]
}
```

- Top-level `five_hour`/`seven_day`/`fetched_at` = the **active** account
  (`activeSlot`), converted from the cache's `resets_at`/`polled_at`. Drives the
  panel readout.
- `accounts` ordered by `slot` (stable — the active one is *marked*, not
  reordered, to avoid list jumpiness).
- **Non-cux fallback:** `"multi": false`, **no** `accounts` array — identical to
  today's output from `usage-fetch.py`.

## UI

### CompactView (panel) — unchanged

Reads top-level `usage.five_hour`/`seven_day`, which now carry the **active
account's** numbers. No code change; satisfies the chosen "active account" panel
readout.

### FullView popup — "Usage limits" section

- **`multi` false (or absent):** renders exactly as today — one `UsageBars`.
- **`multi` true:** a `Repeater` over `usage.accounts`, each account a compact
  block:
  - Header: **alias · email** (alias bold; falls back to email local-part when
    no alias), a small `● active` chip on the active account, and per-account
    "updated Xm ago" from its `polled_at`.
  - Body: the existing **`UsageBars`** component, reused unchanged, passed the
    account object (it already expects `five_hour`/`seven_day`).
  - Ordered by `slot`.
- The single header **⟳ refresh** button + busy spinner stay as-is; clicking it
  runs the same `cux usage refresh` path (a normal `refreshUsage()`).
- The account list lives in a `Flickable` so 4+ accounts scroll inside the popup
  rather than overflowing `preferredHeight`.

Mockup (cux mode):

```
Usage limits                    ⟳
─────────────────────────────────
lam-duc… · vn.trungld@…   ● active   updated 2m ago
  5-hour   [██████░░░░░░░]  41%   resets in 1h57m
  Weekly   [██░░░░░░░░░░░]  14%
─────────────────────────────────
oe · oedevai2@…                      updated 2m ago
  5-hour   [█░░░░░░░░░░░░]  10%   resets in 57m
  Weekly   [██████████░░░]  72%   resets in 3d
```

## Refresh Strategy

Chosen: **the plasmoid drives refresh.** On the existing ~5-minute timer (and on
the manual button), `cux-usage-fetch.py` runs `cux usage refresh` (N API calls,
one per account) then reads the cache. The existing boot-retry timer in
`main.qml` is unchanged and still applies.

## Error / Edge Handling

- **Refresh fails / times out, cache exists** → render stale cache;
  per-account "updated Xm ago" reflects staleness; `status: "ok"`.
- **cux present, cache missing/empty** → `status: "loading"` (→ `error` after
  retries); existing retry timer handles it.
- **Account in `state.json` but absent from cache** (never polled) → block shows
  header + muted "no usage data yet", no bars (not fake zeros).
- **cux binary not found** though `state.json` exists → treat as non-cux,
  single-account fallback.
- **Per-account reauth / rate-limit** — cux's cache doesn't distinguish these; a
  broken account just shows stale data. **Known limitation**, out of scope
  (would require cux to surface per-account error state).

## Testing

- **Unit (Python):** `cux-usage-fetch.py`'s join/fallback logic is pure and
  QML-free. Test with fixture `state.json` + `usage-cache.json`:
  - active account flagged correctly; ordering by slot;
  - missing-from-cache account handled;
  - non-cux fallback emits today's single-account shape;
  - refresh-failure still renders cache.
- **QML:** deploy to the running plasmoid and eyeball the popup (established
  workflow; see the `plasma-qml-conventions` skill).

## Install / Packaging

- `install.sh`: add `cux-usage-fetch.py` to the copied scripts.
- `main.qml`: point `usageCmd` at `cux-usage-fetch.py`.
- No new dependencies (python3 already required; cux optional).

## Out of Scope

- A config toggle to force single-account view while cux is installed (auto-
  detect is sufficient; revisit if requested).
- Surfacing per-account reauth/rate-limit states.
- Switching the active account from the popup.
