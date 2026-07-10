# Claude Status Bar for KDE — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A KDE Plasma 6 plasmoid that shows Claude Code's live activity in the panel and, right-aligned, the account's 5-hour and weekly usage percentages (with a config toggle to hide them).

**Architecture:** Claude Code hooks (configured in `~/.claude/settings.json`) run one Python script that writes a per-session status file. A Python aggregator merges those files; the plasmoid polls it every second for activity. A second Python script fetches subscription usage from the undocumented `/api/oauth/usage` endpoint and caches it; the plasmoid polls it every ~5 min (only when the panel readout is enabled).

**Tech Stack:** Python 3 stdlib (hooks/aggregator/usage — no third-party deps), pytest (tests), QML + KDE Frameworks 6 / Plasma 6 (`org.kde.plasma.plasmoid`, `org.kde.plasma.plasma5support`), Bash (install/uninstall).

## Global Constraints

- **Platform:** KDE Plasma 6 (target verified 6.7.2, Qt6/KF6). Plasmoid metadata must declare `"X-Plasma-API-Minimum-Version": "6.0"`.
- **Python:** stdlib only for all runtime scripts (`urllib.request`, `json`, `os`, `sys`, `time`). Verified interpreter: Python 3.14. Scripts run via `python3`.
- **Hook robustness:** the hook script must NEVER fail Claude Code — wrap the whole body in try/except and always `sys.exit(0)`.
- **Data dir:** `${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar/` with subdirs `bin/`, `sessions/`, and file `usage-cache.json`.
- **Usage endpoint:** `GET https://api.anthropic.com/api/oauth/usage`. MUST send headers `Authorization: Bearer <accessToken>` and `User-Agent: claude-code/<version>` (missing UA → aggressive 429). Token read from `~/.claude/.credentials.json` → `claudeAiOauth.accessToken` / `.expiresAt`. Detected Claude version at build time: `2.1.197`.
- **Usage cadence:** background poll no faster than `USAGE_POLL_INTERVAL=300s`; fetch gated by `USAGE_MIN_INTERVAL=300s` cache freshness. Never on the 1s activity cadence.
- **Staleness:** aggregator drops non-idle session files older than `STALE_SECS=900`.
- **State values:** `state ∈ {"thinking","tool","waiting","idle"}`.
- **Config default:** `showUsageOnPanel = true`.
- **settings.json edits:** always back up first; append to existing hook matcher groups, never overwrite; idempotent.
- **Commit style (repo convention):** `Update:/Fix:/WIP:/Hotfix:` first line, imperative, <72 chars, blank line, body, then `Co-Authored-By: Claude <noreply@anthropic.com>`.

---

## File Structure

```
claude-status-bar-kde/
  scripts/
    statusbar_paths.py          # shared path/dir helpers
    claude-status-hook.py       # hook: event -> session file
    claude-status-aggregate.py  # merge session files -> one JSON line
    usage-fetch.py              # GET /api/oauth/usage -> cache + stdout
    spike-usage.py              # Task 0 feasibility probe (throwaway)
  package/
    metadata.json
    contents/config/main.xml
    contents/config/config.qml
    contents/ui/main.qml
    contents/ui/CompactView.qml
    contents/ui/FullView.qml
    contents/ui/UsageBars.qml
    contents/ui/configGeneral.qml
  tests/
    conftest.py
    test_paths.py
    test_hook.py
    test_aggregate.py
    test_usage_fetch.py
  install.sh
  uninstall.sh
  README.md
```

---

## Task 0: Spike — validate the OAuth usage endpoint (GATE)

Throwaway feasibility probe. The whole usage feature depends on this. Not TDD.

**Files:**
- Create: `scripts/spike-usage.py`

- [ ] **Step 1: Write the spike script**

```python
#!/usr/bin/env python3
"""Throwaway spike: does /api/oauth/usage work with the local token + UA header?"""
import json, os, sys, urllib.request, urllib.error

CRED = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"
UA = "claude-code/2.1.197"

def main():
    tok = json.load(open(CRED))["claudeAiOauth"]["accessToken"]
    for with_ua in (True, False):
        headers = {"Authorization": f"Bearer {tok}"}
        if with_ua:
            headers["User-Agent"] = UA
        req = urllib.request.Request(URL, headers=headers)
        label = "WITH ua" if with_ua else "NO ua"
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                body = r.read().decode()
                print(f"[{label}] HTTP {r.status}")
                print(json.dumps(json.loads(body), indent=2)[:1500])
        except urllib.error.HTTPError as e:
            print(f"[{label}] HTTP {e.code}: {e.read().decode()[:300]}")
        except Exception as e:
            print(f"[{label}] ERROR {type(e).__name__}: {e}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it and read the real response**

Run: `python3 scripts/spike-usage.py`
Expected (success gate): the `WITH ua` call prints `HTTP 200` and JSON containing `five_hour` and `seven_day` objects with a `utilization` number each. Record the exact key names and whether reset timestamps (e.g. `resets_at`) are present — later tasks use them.

- [ ] **Step 3: Decide the gate**

- PASS → note the confirmed JSON shape as a comment at the top of `scripts/usage-fetch.py` in Task 4, and continue.
- FAIL (persistent 429, non-200, different schema, or auth we can't satisfy) → STOP. Report the raw output to the user. The activity indicator (Tasks 1–3, 5) still ships; the usage tasks (4, 6, parts of 7–8) are blocked pending user decision.

- [ ] **Step 4: Commit the spike**

```bash
git add scripts/spike-usage.py
git commit -m "$(printf 'WIP: add OAuth usage endpoint feasibility spike\n\nThrowaway probe confirming /api/oauth/usage returns five_hour and\nseven_day utilization with the local token and the required\nclaude-code User-Agent header.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 1: Shared paths module

**Files:**
- Create: `scripts/statusbar_paths.py`
- Create: `tests/conftest.py`
- Create: `tests/test_paths.py`

**Interfaces:**
- Produces:
  - `data_dir() -> str` — `${XDG_DATA_HOME:-~/.local/share}/claude-status-bar`
  - `sessions_dir() -> str` — `<data_dir>/sessions`
  - `usage_cache_path() -> str` — `<data_dir>/usage-cache.json`
  - `session_file(session_id: str) -> str` — `<sessions_dir>/<session_id>.json`
  - `ensure_dirs() -> None` — creates data + sessions dirs (`exist_ok=True`)
  - `atomic_write_json(path: str, obj: dict) -> None` — temp file in same dir + `os.replace`

- [ ] **Step 1: Write conftest.py (shared fixture)**

```python
import importlib, os, sys
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

@pytest.fixture
def data_home(tmp_path, monkeypatch):
    """Redirect XDG_DATA_HOME so tests never touch the real data dir."""
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    import statusbar_paths
    importlib.reload(statusbar_paths)
    statusbar_paths.ensure_dirs()
    return tmp_path
```

- [ ] **Step 2: Write the failing test**

```python
import json, os

def test_dirs_under_xdg_data_home(data_home):
    import statusbar_paths as p
    assert p.data_dir() == os.path.join(str(data_home), "claude-status-bar")
    assert p.sessions_dir() == os.path.join(p.data_dir(), "sessions")
    assert os.path.isdir(p.sessions_dir())

def test_session_file_path(data_home):
    import statusbar_paths as p
    assert p.session_file("abc") == os.path.join(p.sessions_dir(), "abc.json")

def test_atomic_write_json_roundtrip(data_home):
    import statusbar_paths as p
    target = os.path.join(p.data_dir(), "x.json")
    p.atomic_write_json(target, {"a": 1})
    assert json.load(open(target)) == {"a": 1}
    # no leftover temp files
    assert [f for f in os.listdir(p.data_dir()) if f.endswith(".json")] == ["x.json"]
```

- [ ] **Step 3: Run test to verify it fails**

Run: `python3 -m pytest tests/test_paths.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'statusbar_paths'`.

- [ ] **Step 4: Write the implementation**

```python
"""Shared filesystem helpers for the Claude status bar scripts (stdlib only)."""
import json, os, tempfile

def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "claude-status-bar")

def sessions_dir():
    return os.path.join(data_dir(), "sessions")

def usage_cache_path():
    return os.path.join(data_dir(), "usage-cache.json")

def session_file(session_id):
    return os.path.join(sessions_dir(), session_id + ".json")

def ensure_dirs():
    os.makedirs(sessions_dir(), exist_ok=True)

def atomic_write_json(path, obj):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python3 -m pytest tests/test_paths.py -v`
Expected: PASS (3 passed).

- [ ] **Step 6: Commit**

```bash
git add scripts/statusbar_paths.py tests/conftest.py tests/test_paths.py
git commit -m "$(printf 'Update: add shared path helpers for status bar scripts\n\nAdd statusbar_paths with XDG-aware data/sessions dir resolution and an\natomic JSON writer, plus a conftest fixture that redirects\nXDG_DATA_HOME so tests are hermetic.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 2: Hook script

**Files:**
- Create: `scripts/claude-status-hook.py`
- Create: `tests/test_hook.py`

**Interfaces:**
- Consumes: `statusbar_paths` (Task 1).
- Invocation: `claude-status-hook.py <EventName>` with the hook payload JSON on stdin.
- Produces: writes/updates/deletes `sessions/<session_id>.json` with schema
  `{session_id, state, tool, started_at, updated_at, cwd}`. `started_at`/`tool` may be absent/null.

- [ ] **Step 1: Write the failing test**

```python
import json, subprocess, sys, os

HOOK = os.path.join(os.path.dirname(__file__), "..", "scripts", "claude-status-hook.py")

def run(event, payload, env):
    return subprocess.run([sys.executable, HOOK, event],
                          input=json.dumps(payload), text=True,
                          capture_output=True, env=env)

def _env(data_home):
    e = dict(os.environ); e["XDG_DATA_HOME"] = str(data_home); return e

def read_session(p, sid):
    return json.load(open(p.session_file(sid)))

def test_userpromptsubmit_sets_thinking_and_started(data_home):
    import statusbar_paths as p
    r = run("UserPromptSubmit", {"session_id": "s1", "cwd": "/tmp/x"}, _env(data_home))
    assert r.returncode == 0
    doc = read_session(p, "s1")
    assert doc["state"] == "thinking"
    assert doc["cwd"] == "/tmp/x"
    assert isinstance(doc["started_at"], (int, float))

def test_pretooluse_sets_tool_and_keeps_started(data_home):
    import statusbar_paths as p
    run("UserPromptSubmit", {"session_id": "s1"}, _env(data_home))
    started = read_session(p, "s1")["started_at"]
    run("PreToolUse", {"session_id": "s1", "tool_name": "Edit"}, _env(data_home))
    doc = read_session(p, "s1")
    assert doc["state"] == "tool" and doc["tool"] == "Edit"
    assert doc["started_at"] == started  # not reset

def test_posttooluse_back_to_thinking(data_home):
    import statusbar_paths as p
    run("UserPromptSubmit", {"session_id": "s1"}, _env(data_home))
    run("PreToolUse", {"session_id": "s1", "tool_name": "Bash"}, _env(data_home))
    run("PostToolUse", {"session_id": "s1", "tool_name": "Bash"}, _env(data_home))
    assert read_session(p, "s1")["state"] == "thinking"

def test_notification_sets_waiting(data_home):
    import statusbar_paths as p
    run("Notification", {"session_id": "s1"}, _env(data_home))
    assert read_session(p, "s1")["state"] == "waiting"

def test_stop_sets_idle_and_clears_started(data_home):
    import statusbar_paths as p
    run("UserPromptSubmit", {"session_id": "s1"}, _env(data_home))
    run("Stop", {"session_id": "s1"}, _env(data_home))
    doc = read_session(p, "s1")
    assert doc["state"] == "idle" and doc["started_at"] is None

def test_sessionend_deletes_file(data_home):
    import statusbar_paths as p
    run("SessionStart", {"session_id": "s1"}, _env(data_home))
    assert os.path.exists(p.session_file("s1"))
    run("SessionEnd", {"session_id": "s1"}, _env(data_home))
    assert not os.path.exists(p.session_file("s1"))

def test_malformed_stdin_exits_zero(data_home):
    r = subprocess.run([sys.executable, HOOK, "PreToolUse"],
                       input="not json", text=True, capture_output=True,
                       env=_env(data_home))
    assert r.returncode == 0  # never break Claude Code

def test_missing_session_id_exits_zero(data_home):
    r = run("PreToolUse", {"tool_name": "Edit"}, _env(data_home))
    assert r.returncode == 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_hook.py -v`
Expected: FAIL — hook script missing / non-zero exit.

- [ ] **Step 3: Write the implementation**

```python
#!/usr/bin/env python3
"""Claude Code hook: translate one hook event into a per-session status file.

Usage: claude-status-hook.py <EventName>   (payload JSON on stdin)
Must never fail Claude Code: always exits 0.
"""
import json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def main():
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    payload = json.load(sys.stdin)
    sid = payload.get("session_id")
    if not sid:
        return
    import statusbar_paths as p

    if event == "SessionEnd":
        try:
            os.unlink(p.session_file(sid))
        except OSError:
            pass
        return

    path = p.session_file(sid)
    try:
        doc = json.load(open(path))
    except (OSError, ValueError):
        doc = {"session_id": sid, "state": "idle", "tool": None,
               "started_at": None, "updated_at": 0, "cwd": None}

    now = int(time.time())
    doc["session_id"] = sid
    doc["updated_at"] = now
    if payload.get("cwd"):
        doc["cwd"] = payload["cwd"]

    if event == "SessionStart":
        doc["state"] = "idle"
    elif event == "UserPromptSubmit":
        doc["state"] = "thinking"
        if not doc.get("started_at"):
            doc["started_at"] = now
    elif event == "PreToolUse":
        doc["state"] = "tool"
        doc["tool"] = payload.get("tool_name")
    elif event in ("PostToolUse", "PostToolUseFailure"):
        doc["state"] = "thinking"
        doc["tool"] = None
    elif event == "Notification":
        doc["state"] = "waiting"
    elif event == "Stop":
        doc["state"] = "idle"
        doc["started_at"] = None
        doc["tool"] = None

    p.atomic_write_json(path, doc)

if __name__ == "__main__":
    try:
        main()
    except BaseException:
        pass
    sys.exit(0)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_hook.py -v`
Expected: PASS (8 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/claude-status-hook.py tests/test_hook.py
git commit -m "$(printf 'Update: add Claude Code hook to write per-session status\n\nAdd claude-status-hook.py dispatching on the event name to update a\nper-session JSON file (thinking/tool/waiting/idle), keeping started_at\nacross tool calls and clearing it on Stop. Wrapped so it always exits 0\nand never breaks Claude Code, even on malformed stdin.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 3: Aggregator

**Files:**
- Create: `scripts/claude-status-aggregate.py`
- Create: `tests/test_aggregate.py`

**Interfaces:**
- Consumes: `statusbar_paths` (Task 1); session files written by Task 2.
- Produces: prints ONE JSON line to stdout:
  `{state, tool, started_at, active_count, waiting_count, sessions:[...]}`.
  Provides testable pure function `aggregate(docs: list[dict], now: int) -> dict`.

- [ ] **Step 1: Write the failing test**

```python
import importlib, json, os, subprocess, sys

AGG = os.path.join(os.path.dirname(__file__), "..", "scripts", "claude-status-aggregate.py")

def load_agg():
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
    import claude_status_aggregate as m  # hyphen file imported via importlib below
    return m

def _agg():
    import importlib.util
    spec = importlib.util.spec_from_file_location("agg", AGG)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

def d(sid, state, started=None, updated=1000, tool=None):
    return {"session_id": sid, "state": state, "tool": tool,
            "started_at": started, "updated_at": updated, "cwd": "/w/" + sid}

def test_all_idle():
    m = _agg()
    out = m.aggregate([d("a", "idle"), d("b", "idle")], now=1000)
    assert out["state"] == "idle" and out["active_count"] == 0

def test_waiting_beats_tool_and_thinking():
    m = _agg()
    docs = [d("a", "thinking", 500), d("b", "tool", 600, tool="Edit"), d("c", "waiting")]
    out = m.aggregate(docs, now=1000)
    assert out["state"] == "waiting" and out["waiting_count"] == 1

def test_tool_beats_thinking_and_reports_latest_tool():
    m = _agg()
    docs = [d("a", "thinking", 500, updated=900),
            d("b", "tool", 600, updated=950, tool="Bash")]
    out = m.aggregate(docs, now=1000)
    assert out["state"] == "tool" and out["tool"] == "Bash"
    assert out["active_count"] == 2

def test_thinking_uses_earliest_started():
    m = _agg()
    docs = [d("a", "thinking", started=800), d("b", "thinking", started=600)]
    out = m.aggregate(docs, now=1000)
    assert out["state"] == "thinking" and out["started_at"] == 600

def test_stale_nonidle_dropped():
    m = _agg()
    # updated_at far in the past, not idle -> dropped (STALE_SECS=900)
    out = m.aggregate([d("a", "tool", 100, updated=1, tool="Edit")], now=100000)
    assert out["state"] == "idle" and out["active_count"] == 0

def test_cli_reads_session_dir(data_home):
    import statusbar_paths as p
    p.atomic_write_json(p.session_file("s1"),
                        d("s1", "waiting", updated=999999999999))
    env = dict(os.environ); env["XDG_DATA_HOME"] = str(data_home)
    r = subprocess.run([sys.executable, AGG], capture_output=True, text=True, env=env)
    out = json.loads(r.stdout)
    assert out["state"] == "waiting"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_aggregate.py -v`
Expected: FAIL — aggregator file missing.

- [ ] **Step 3: Write the implementation**

```python
#!/usr/bin/env python3
"""Merge all per-session status files into one aggregate JSON line on stdout."""
import glob, json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

STALE_SECS = 900
PRIORITY = {"waiting": 3, "tool": 2, "thinking": 1, "idle": 0}

def aggregate(docs, now):
    live = [x for x in docs
            if not (x.get("state") != "idle"
                    and now - int(x.get("updated_at") or 0) > STALE_SECS)]
    active = [x for x in live if x.get("state") in ("thinking", "tool", "waiting")]
    waiting = [x for x in active if x["state"] == "waiting"]
    tools = [x for x in active if x["state"] == "tool"]

    if waiting:
        state, tool = "waiting", None
    elif tools:
        state = "tool"
        tool = max(tools, key=lambda x: int(x.get("updated_at") or 0)).get("tool")
    elif active:
        state, tool = "thinking", None
    else:
        state, tool = "idle", None

    starts = [int(x["started_at"]) for x in active if x.get("started_at")]
    started_at = min(starts) if starts else None

    return {"state": state, "tool": tool, "started_at": started_at,
            "active_count": len(active), "waiting_count": len(waiting),
            "sessions": live}

def load_docs():
    import statusbar_paths as p
    docs = []
    for f in glob.glob(os.path.join(p.sessions_dir(), "*.json")):
        try:
            docs.append(json.load(open(f)))
        except (OSError, ValueError):
            continue
    return docs

if __name__ == "__main__":
    print(json.dumps(aggregate(load_docs(), int(time.time()))))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_aggregate.py -v`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/claude-status-aggregate.py tests/test_aggregate.py
git commit -m "$(printf 'Update: add session status aggregator\n\nAdd claude-status-aggregate.py merging all per-session files into one\nJSON line by priority (waiting>tool>thinking>idle), using the earliest\nstarted_at for the timer and dropping stale non-idle sessions after 15\nminutes.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 4: Usage fetcher

Blocked if Task 0 failed. Uses the JSON shape confirmed by the spike.

**Files:**
- Create: `scripts/usage-fetch.py`
- Create: `tests/test_usage_fetch.py`

**Interfaces:**
- Consumes: `statusbar_paths` (Task 1); `~/.claude/.credentials.json`.
- Produces: prints ONE JSON line and writes it to `usage_cache_path()`:
  `{status, fetched_at, five_hour, seven_day}` where `status ∈ {"ok","rate_limited","reauth","error"}`.
- Testable pure function:
  `build_result(now, http_status, body, prev_cache) -> dict`.

- [ ] **Step 1: Write the failing test**

```python
import importlib.util, json, os

UF = os.path.join(os.path.dirname(__file__), "..", "scripts", "usage-fetch.py")

def _mod():
    spec = importlib.util.spec_from_file_location("uf", UF)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

OK_BODY = json.dumps({"five_hour": {"utilization": 42},
                      "seven_day": {"utilization": 18}})

def test_ok_response_parsed():
    m = _mod()
    out = m.build_result(now=100, http_status=200, body=OK_BODY, prev_cache=None)
    assert out["status"] == "ok"
    assert out["five_hour"]["utilization"] == 42
    assert out["seven_day"]["utilization"] == 18
    assert out["fetched_at"] == 100

def test_429_keeps_prev_values():
    m = _mod()
    prev = {"status": "ok", "fetched_at": 1, "five_hour": {"utilization": 40},
            "seven_day": {"utilization": 10}}
    out = m.build_result(now=200, http_status=429, body="", prev_cache=prev)
    assert out["status"] == "rate_limited"
    assert out["five_hour"]["utilization"] == 40  # preserved

def test_401_is_reauth():
    m = _mod()
    out = m.build_result(now=1, http_status=401, body="", prev_cache=None)
    assert out["status"] == "reauth"

def test_error_status_without_prev():
    m = _mod()
    out = m.build_result(now=1, http_status=500, body="", prev_cache=None)
    assert out["status"] == "error"

def test_load_prev_cache_missing_returns_none(data_home):
    m = _mod()
    assert m.load_prev_cache() is None  # no cache file yet
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_usage_fetch.py -v`
Expected: FAIL — usage-fetch file missing.

- [ ] **Step 3: Write the implementation**

```python
#!/usr/bin/env python3
"""Fetch Claude subscription usage from /api/oauth/usage; cache + print JSON.

Spike-confirmed shape: {"five_hour":{"utilization":N}, "seven_day":{"utilization":N}}
(adjust the keys here if Task 0 recorded different ones).
"""
import json, os, sys, time, urllib.request, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

CRED = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"
UA = "claude-code/2.1.197"  # baked at install time from `claude --version`

def load_prev_cache():
    import statusbar_paths as p
    try:
        return json.load(open(p.usage_cache_path()))
    except (OSError, ValueError):
        return None

def build_result(now, http_status, body, prev_cache):
    prev = prev_cache or {}
    if http_status == 200:
        data = json.loads(body)
        return {"status": "ok", "fetched_at": now,
                "five_hour": data.get("five_hour", {}),
                "seven_day": data.get("seven_day", {})}
    if http_status == 401:
        status = "reauth"
    elif http_status == 429:
        status = "rate_limited"
    else:
        status = "error"
    return {"status": status, "fetched_at": prev.get("fetched_at"),
            "five_hour": prev.get("five_hour", {}),
            "seven_day": prev.get("seven_day", {})}

def read_token():
    creds = json.load(open(CRED))["claudeAiOauth"]
    return creds.get("accessToken"), creds.get("expiresAt")

def http_get(token):
    req = urllib.request.Request(
        URL, headers={"Authorization": f"Bearer {token}", "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:
        return 0, ""

def main():
    import statusbar_paths as p
    now = int(time.time())
    prev = load_prev_cache()
    token, expires_at = read_token()
    if not token or (expires_at and now * 1000 >= int(expires_at)):
        result = {"status": "reauth", "fetched_at": prev.get("fetched_at") if prev else None,
                  "five_hour": (prev or {}).get("five_hour", {}),
                  "seven_day": (prev or {}).get("seven_day", {})}
    else:
        code, body = http_get(token)
        result = build_result(now, code, body, prev)
    if result["status"] != "rate_limited":  # respect backoff: don't churn cache on 429
        p.atomic_write_json(p.usage_cache_path(), result)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_usage_fetch.py -v`
Expected: PASS (5 passed).

- [ ] **Step 5: Verify against the live endpoint once**

Run: `python3 scripts/usage-fetch.py`
Expected: a JSON line with `"status": "ok"` and real `utilization` numbers (matching Task 0). If `rate_limited`/`reauth`, note it but the code path is correct.

- [ ] **Step 6: Commit**

```bash
git add scripts/usage-fetch.py tests/test_usage_fetch.py
git commit -m "$(printf 'Update: add subscription usage fetcher\n\nAdd usage-fetch.py querying /api/oauth/usage with the local token and\nthe required claude-code User-Agent header, caching the 5-hour and\nweekly utilization. Handles 200/401/429/error into a status field and\npreserves the last cache on rate limiting without advancing it.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 5: Plasmoid skeleton + activity compact view

Delivers a runnable plasmoid showing activity only (no usage yet). Verified with `plasmawindowed`.

**Files:**
- Create: `package/metadata.json`
- Create: `package/contents/ui/main.qml`
- Create: `package/contents/ui/CompactView.qml`
- Create: `package/contents/ui/FullView.qml` (placeholder popup)

**Interfaces:**
- Consumes: `claude-status-aggregate.py` on stdout (Task 3).
- Produces: `main.qml` exposes `root.agg` (parsed aggregate object) and
  `root.aggCmd` (command string) to child views; `CompactView`/`FullView` read `root.agg`.

- [ ] **Step 1: Write metadata.json**

```json
{
    "KPackageStructure": "Plasma/Applet",
    "KPlugin": {
        "Id": "org.kde.claudestatusbar",
        "Name": "Claude Status Bar",
        "Description": "Live Claude Code activity and usage in the panel",
        "Icon": "utilities-terminal",
        "Category": "System Information",
        "Version": "0.1",
        "Authors": [{ "Name": "trungld" }]
    },
    "X-Plasma-API-Minimum-Version": "6.0"
}
```

- [ ] **Step 2: Write main.qml**

```qml
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // The installer always writes scripts here (XDG_DATA_HOME rarely differs;
    // the shell wrapper below expands it at runtime).
    readonly property string binDir:
        "${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar/bin"
    readonly property string aggCmd: "python3 " + binDir + "/claude-status-aggregate.py"
    // usagePath/usageCmd added in Task 6.

    property var agg: ({ state: "idle", tool: null, started_at: null,
                         active_count: 0, waiting_count: 0, sessions: [] })

    // Executable engine runs the command through /bin/sh, so the ${XDG...}
    // expansion in binDir is resolved by the shell — no manual env lookup.
    Plasma5Support.DataSource {
        id: aggSrc
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)  // allow the same command to re-run next tick
            try { root.agg = JSON.parse((data["stdout"] || "").trim()) }
            catch (e) { /* keep previous value */ }
        }
        function run(cmd) { connectSource(cmd) }
    }

    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: aggSrc.run(root.aggCmd)
    }

    compactRepresentation: CompactView {}
    fullRepresentation: FullView {}
}
```

- [ ] **Step 3: Write CompactView.qml**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

MouseArea {
    id: compact
    Layout.minimumWidth: row.implicitWidth
    onClicked: plasmoid.expanded = !plasmoid.expanded

    readonly property var agg: root.agg

    function toolLabel(t) {
        switch (t) {
        case "Edit": case "Write": case "MultiEdit": return "Editing"
        case "Bash": return "Running"
        case "Read": return "Reading"
        case "Grep": case "Glob": return "Searching"
        case "WebFetch": case "WebSearch": return "Browsing"
        case "Task": return "Delegating"
        default: return t || ""
        }
    }

    property int elapsed: 0
    Timer {
        interval: 1000; repeat: true
        running: agg.started_at !== null
        triggeredOnStart: true
        onTriggered: elapsed = Math.max(0, Math.floor(Date.now()/1000) - agg.started_at)
    }
    function fmt(s) {
        var m = Math.floor(s/60); return m > 0 ? (m + "m " + (s%60) + "s") : (s + "s")
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 4
        PlasmaComponents.Label {
            text: agg.state === "waiting" ? "●" : "◆"
            color: agg.state === "waiting" ? "#f5c451" : palette.text
        }
        PlasmaComponents.Label {
            visible: agg.state === "tool"
            text: toolLabel(agg.tool)
        }
        PlasmaComponents.Label {
            visible: agg.started_at !== null
            text: fmt(compact.elapsed)
        }
    }
}
```

- [ ] **Step 4: Write FullView.qml (placeholder)**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    Layout.minimumWidth: 260
    Layout.minimumHeight: 120
    PlasmaComponents.Label { text: "Claude sessions: " + root.agg.active_count }
    Repeater {
        model: root.agg.sessions
        PlasmaComponents.Label {
            text: modelData.session_id.substring(0, 8) + " — " + modelData.state
        }
    }
}
```

- [ ] **Step 5: Install locally and run the plasmoid standalone**

```bash
kpackagetool6 --type Plasma/Applet --install package/ 2>/dev/null \
  || kpackagetool6 --type Plasma/Applet --upgrade package/
# Provide a fake aggregator so there is something to read:
mkdir -p "$HOME/.local/share/claude-status-bar/bin"
printf '#!/usr/bin/env python3\nprint(\x27{"state":"tool","tool":"Edit","started_at":%d,"active_count":1,"waiting_count":0,"sessions":[{"session_id":"abcd1234","state":"tool"}]}\x27 %% 0)\n' > /tmp/agg.py
cp scripts/claude-status-aggregate.py "$HOME/.local/share/claude-status-bar/bin/"
plasmawindowed org.kde.claudestatusbar
```

Expected: a window opens showing the compact view (a `◆` glyph; with real session files it shows tool label + timer). Clicking expands the placeholder popup. (If nothing renders, check `QT_LOGGING_RULES="qml=true" plasmawindowed org.kde.claudestatusbar` for QML errors.)

- [ ] **Step 6: Verify live activity end-to-end (manual)**

```bash
# Simulate a session becoming active, then run the real aggregator:
python3 scripts/claude-status-hook.py UserPromptSubmit <<< '{"session_id":"demo","cwd":"/tmp"}'
python3 scripts/claude-status-hook.py PreToolUse <<< '{"session_id":"demo","tool_name":"Edit"}'
python3 scripts/claude-status-aggregate.py
```

Expected: the aggregator prints `"state": "tool"`, and the plasmoid window (pointing at the installed aggregator) shows `Editing` + a running timer within ~1s.

- [ ] **Step 7: Commit**

```bash
git add package/metadata.json package/contents/ui/main.qml package/contents/ui/CompactView.qml package/contents/ui/FullView.qml
git commit -m "$(printf 'Update: add plasmoid skeleton with activity compact view\n\nAdd the Plasma 6 plasmoid package: metadata, main.qml polling the\naggregator every second via an executable DataSource, a compact view\nshowing state glyph, tool label and elapsed timer, and a placeholder\npopup listing sessions. Verified standalone with plasmawindowed.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 6: Panel usage readout + usage DataSource

Blocked if Task 0 failed. Adds the right-aligned `5h % · 7d %`.

**Files:**
- Modify: `package/contents/ui/main.qml` (add usage DataSource + `root.usage`)
- Modify: `package/contents/ui/CompactView.qml` (right-aligned readout)

**Interfaces:**
- Consumes: `usage-fetch.py` stdout (Task 4).
- Produces: `root.usage` object `{status, five_hour, seven_day}`; `root.usagePath`.

- [ ] **Step 1: Extend main.qml with a usage source**

Add inside `PlasmoidItem` (after the activity block), reusing `root.binDir`:

```qml
    readonly property string usageCmd: "python3 " + binDir + "/usage-fetch.py"
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    Plasma5Support.DataSource {
        id: usageSrc
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            try { root.usage = JSON.parse((data["stdout"] || "").trim()) }
            catch (e) { /* keep previous */ }
        }
        function run(cmd) { connectSource(cmd) }
    }

    Timer {
        id: usageTimer
        interval: 300000; repeat: true
        running: false   // enabled in Task 7 by the config toggle
        triggeredOnStart: true
        onTriggered: usageSrc.run(root.usageCmd)
    }
```

Also update the two representation lines (added in Task 5) to pass `usage`
down as well — child files cannot see `root` (ids are file-scoped), so data
must be passed as properties:

```qml
    compactRepresentation: CompactView { agg: root.agg; usage: root.usage }
    fullRepresentation: FullView { agg: root.agg; usage: root.usage }
```

- [ ] **Step 2: Add the readout to CompactView.qml**

First declare the `usage` property on CompactView's root (so main can bind it):

```qml
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })
```

Then insert into the `RowLayout`, after the existing labels (reference the
local `usage`, never `root.usage`):

```qml
        Item { Layout.fillWidth: true }   // spacer pushes usage to the right
        PlasmaComponents.Label {
            id: usageLabel
            visible: true   // bound to the config toggle in Task 7
            function pct(w) { return (w && w.utilization !== undefined) ? Math.round(w.utilization) : null }
            function part(prefix, w) { var v = pct(w); return prefix + (v === null ? "—" : v) + "%" }
            text: part("5h ", usage.five_hour) + " · " + part("7d ", usage.seven_day)
            opacity: usage.status === "ok" ? 1.0 : 0.5
            color: {
                var v = Math.max(pct(usage.five_hour) || 0, pct(usage.seven_day) || 0)
                return v > 90 ? "#e05252" : (v > 70 ? "#f5c451" : palette.text)
            }
        }
```

- [ ] **Step 3: Enable the usage timer for the manual check**

Temporarily set `usageTimer.running: true` (Task 7 replaces this with the config binding). Copy the real usage script into the installed bin and re-run:

```bash
cp scripts/usage-fetch.py scripts/statusbar_paths.py "$HOME/.local/share/claude-status-bar/bin/"
kpackagetool6 --type Plasma/Applet --upgrade package/
plasmawindowed org.kde.claudestatusbar
```

Expected: the compact view now shows `5h N% · 7d N%` on the right, colour-graded, matching `python3 scripts/usage-fetch.py` output. If `status != ok`, values render dimmed / `—%`.

- [ ] **Step 4: Revert the temporary `running: true` back to `false`**

Leave `usageTimer.running: false` (Task 7 binds it). Confirm the file diff shows `running: false`.

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/main.qml package/contents/ui/CompactView.qml
git commit -m "$(printf 'Update: add right-aligned 5h/weekly usage readout\n\nAdd a second executable DataSource polling usage-fetch.py and a\nright-aligned \"5h %% · 7d %%\" label in the compact view, colour-graded\nby the higher window and dimmed when the fetch is not ok. Poll timer\nleft disabled here; wired to the config toggle next.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 7: Config toggle (show/hide panel usage)

**Files:**
- Create: `package/contents/config/main.xml`
- Create: `package/contents/config/config.qml`
- Create: `package/contents/ui/configGeneral.qml`
- Modify: `package/contents/ui/main.qml` (bind usage timer to config)
- Modify: `package/contents/ui/CompactView.qml` (bind label visibility to config)

**Interfaces:**
- Produces: config key `showUsageOnPanel` (bool, default true) at
  `plasmoid.configuration.showUsageOnPanel`.

- [ ] **Step 1: Write config/main.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0">
  <kcfgfile name=""/>
  <group name="General">
    <entry name="showUsageOnPanel" type="Bool">
      <default>true</default>
    </entry>
  </group>
</kcfg>
```

- [ ] **Step 2: Write config/config.qml**

```qml
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
}
```

- [ ] **Step 3: Write ui/configGeneral.qml**

```qml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_showUsageOnPanel: usageCheck.checked

    QQC2.CheckBox {
        id: usageCheck
        Kirigami.FormData.label: i18n("Usage:")
        text: i18n("Show 5-hour and weekly usage % on the panel")
    }
}
```

- [ ] **Step 4: Bind the timer and label to the toggle**

In `main.qml`, change the usage timer to:

```qml
        running: plasmoid.configuration.showUsageOnPanel
```

In `CompactView.qml`, change the usage label to:

```qml
            visible: plasmoid.configuration.showUsageOnPanel
```

- [ ] **Step 5: Verify the toggle live**

```bash
kpackagetool6 --type Plasma/Applet --upgrade package/
plasmawindowed org.kde.claudestatusbar
```

Expected: right-click → Configure shows the "General" page with the checkbox. Unchecking hides the `5h % · 7d %` readout and (confirm via no new network) stops the 5-min poll; re-checking shows it again — no restart needed.

- [ ] **Step 6: Commit**

```bash
git add package/contents/config/main.xml package/contents/config/config.qml package/contents/ui/configGeneral.qml package/contents/ui/main.qml package/contents/ui/CompactView.qml
git commit -m "$(printf 'Update: add config toggle to show/hide panel usage %%\n\nAdd the showUsageOnPanel config key (default true) with a General\nsettings page, and bind the compact usage label visibility and the\nbackground usage poll timer to it so disabling hides the readout and\nstops querying the endpoint. Live, no restart.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 8: Full popup — sessions + usage bars

**Files:**
- Create: `package/contents/ui/UsageBars.qml`
- Modify: `package/contents/ui/FullView.qml` (real popup)

**Interfaces:**
- Consumes: `agg` and `usage` passed in as properties (child files cannot see
  `root` — ids are file-scoped). `FullView` receives both from `main.qml`
  (Task 5/6) and forwards `usage` into `UsageBars`.

- [ ] **Step 1: Write UsageBars.qml**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    Layout.fillWidth: true
    spacing: 4

    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })
    function pct(w) { return (w && w.utilization !== undefined) ? Math.round(w.utilization) : null }

    PlasmaComponents.Label {
        visible: usage.status !== "ok"
        text: usage.status === "reauth" ? i18n("Sign in to Claude to see usage")
            : usage.status === "rate_limited" ? i18n("Usage rate-limited — showing last known")
            : usage.status === "error" ? i18n("Usage unavailable")
            : i18n("Loading usage…")
        opacity: 0.7
    }
    Repeater {
        model: [{ label: i18n("5-hour"), w: usage.five_hour },
                { label: i18n("Weekly"), w: usage.seven_day }]
        RowLayout {
            Layout.fillWidth: true
            visible: pct(modelData.w) !== null
            PlasmaComponents.Label { text: modelData.label; Layout.preferredWidth: 70 }
            PlasmaComponents.ProgressBar {
                Layout.fillWidth: true
                from: 0; to: 100; value: pct(modelData.w) || 0
            }
            PlasmaComponents.Label { text: (pct(modelData.w) || 0) + "%" }
        }
    }
}
```

- [ ] **Step 2: Rewrite FullView.qml**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    Layout.minimumWidth: 300
    Layout.minimumHeight: 200
    spacing: Kirigami.Units.smallSpacing

    // Passed in from main.qml (Task 5/6); child files can't reach root.
    property var agg: ({ active_count: 0, sessions: [] })
    property var usage: ({ status: "loading", five_hour: {}, seven_day: {} })

    PlasmaComponents.Label {
        text: i18n("Claude Code — %1 active", agg.active_count)
        font.bold: true
    }
    Repeater {
        model: agg.sessions
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label { text: (modelData.cwd || "").split("/").pop() || modelData.session_id.substring(0,8) }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: modelData.state + (modelData.tool ? " · " + modelData.tool : "")
                opacity: 0.8
            }
        }
    }
    Kirigami.Separator { Layout.fillWidth: true }
    PlasmaComponents.Label { text: i18n("Usage limits"); font.bold: true }
    UsageBars { usage: parent.usage }
}
```

Note: `UsageBars { usage: parent.usage }` — `parent` here is the FullView
ColumnLayout, whose `usage` property was passed from main.qml. (If `parent`
resolves to an intermediate layout at runtime, give the ColumnLayout an
`id: fullRoot` and use `usage: fullRoot.usage` instead.)

- [ ] **Step 3: Verify the popup**

```bash
kpackagetool6 --type Plasma/Applet --upgrade package/
plasmawindowed org.kde.claudestatusbar
```

Expected: clicking the compact view opens a popup listing sessions (dir name + state/tool) and two usage progress bars (5-hour, Weekly) with percentages; non-ok statuses show the inline message instead of misleading full bars.

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/UsageBars.qml package/contents/ui/FullView.qml
git commit -m "$(printf 'Update: add popup with session list and usage bars\n\nReplace the placeholder popup with a session list (working dir and\nstate/tool) and a UsageBars component showing 5-hour and weekly\nprogress bars, degrading to an inline message on reauth/rate-limit/\nerror states.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 9: Install / uninstall scripts

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`
- Create: `tests/test_install_merge.py` (unit-test the settings.json merge)

**Interfaces:**
- Consumes: all scripts + the plasmoid package.
- The settings.json merge logic lives in an inline Python heredoc; the test
  exercises the same merge function via a small importable module path.

- [ ] **Step 1: Write the merge test (pure Python function)**

Create `scripts/settings_merge.py`:

```python
"""Merge our hooks into a Claude Code settings dict. Idempotent, additive."""
HOOK_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
               "PostToolUseFailure", "Notification", "Stop", "SessionEnd"]

def hook_command(bin_dir, event):
    return f"python3 {bin_dir}/claude-status-hook.py {event}"

def merge(settings, bin_dir):
    hooks = settings.setdefault("hooks", {})
    for event in HOOK_EVENTS:
        cmd = hook_command(bin_dir, event)
        groups = hooks.setdefault(event, [])
        # dedup: skip if any group already has this exact command
        if any(h.get("command") == cmd
               for g in groups for h in g.get("hooks", [])):
            continue
        groups.append({"matcher": "*", "hooks": [{"type": "command", "command": cmd}]})
    return settings
```

Create `tests/test_install_merge.py`:

```python
import importlib.util, os
SM = os.path.join(os.path.dirname(__file__), "..", "scripts", "settings_merge.py")
def _mod():
    spec = importlib.util.spec_from_file_location("sm", SM)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def test_merge_adds_all_events_once():
    m = _mod()
    out = m.merge({}, "/data/bin")
    for ev in m.HOOK_EVENTS:
        cmds = [h["command"] for g in out["hooks"][ev] for h in g["hooks"]]
        assert m.hook_command("/data/bin", ev) in cmds

def test_merge_is_idempotent():
    m = _mod()
    out = m.merge(m.merge({}, "/data/bin"), "/data/bin")
    grp = out["hooks"]["PreToolUse"]
    assert len(grp) == 1  # not duplicated

def test_merge_preserves_existing_hooks():
    m = _mod()
    existing = {"hooks": {"PreToolUse": [
        {"matcher": "*", "hooks": [{"type": "command", "command": "other.sh"}]}]}}
    out = m.merge(existing, "/data/bin")
    cmds = [h["command"] for g in out["hooks"]["PreToolUse"] for h in g["hooks"]]
    assert "other.sh" in cmds and m.hook_command("/data/bin", "PreToolUse") in cmds
```

- [ ] **Step 2: Run test to verify it fails, then passes**

Run: `python3 -m pytest tests/test_install_merge.py -v`
Expected: FAIL (module missing) → after creating `settings_merge.py`, PASS (3 passed).

- [ ] **Step 3: Write install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-status-bar"
BIN="$DATA/bin"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing scripts to $BIN"
mkdir -p "$BIN"
cp "$HERE"/scripts/statusbar_paths.py "$HERE"/scripts/claude-status-hook.py \
   "$HERE"/scripts/claude-status-aggregate.py "$HERE"/scripts/usage-fetch.py "$BIN/"
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
```

- [ ] **Step 4: Create `scripts/apply_settings_merge.py` (called by install.sh)**

```python
#!/usr/bin/env python3
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from settings_merge import merge
settings_path, bin_dir = sys.argv[1], sys.argv[2]
try:
    settings = json.load(open(settings_path))
except (OSError, ValueError):
    settings = {}
merge(settings, bin_dir)
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print(f"Merged hooks into {settings_path}")
```

- [ ] **Step 5: Write uninstall.sh**

```bash
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
```

- [ ] **Step 6: Verify install/uninstall on a throwaway settings file**

```bash
TMP=$(mktemp -d); export XDG_DATA_HOME="$TMP/share"
cp -r . "$TMP/src"; mkdir -p "$TMP/home/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"keep.sh"}]}]}}' > "$TMP/home/.claude/settings.json"
HOME="$TMP/home" bash "$TMP/src/install.sh" || true
python3 -c "import json;d=json.load(open('$TMP/home/.claude/settings.json'));print('keep.sh kept:', any('keep.sh' in h['command'] for g in d['hooks']['PreToolUse'] for h in g['hooks']));print('ours added:', any('claude-status-hook.py' in h['command'] for g in d['hooks']['PreToolUse'] for h in g['hooks']))"
```

Expected: prints `keep.sh kept: True` and `ours added: True`; scripts present in `$XDG_DATA_HOME/claude-status-bar/bin`.

- [ ] **Step 7: Commit**

```bash
git add install.sh uninstall.sh scripts/settings_merge.py scripts/apply_settings_merge.py tests/test_install_merge.py
git commit -m "$(printf 'Update: add install/uninstall scripts with settings merge\n\nAdd install.sh (copy scripts, bake claude version into the UA header,\nadditively merge hooks into settings.json with a timestamped backup,\ninstall the plasmoid) and uninstall.sh (remove plasmoid, strip only our\nhook entries). Merge logic in settings_merge.py is unit-tested for\nidempotency and preservation of existing hooks.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Task 10: README + full-suite verification

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

````markdown
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
````

- [ ] **Step 2: Run the full Python test suite**

Run: `python3 -m pytest tests/ -v`
Expected: all tests pass (paths, hook, aggregate, usage_fetch, install_merge).

- [ ] **Step 3: Final manual smoke test**

Reinstall (`./install.sh`), add the widget to a real panel, start a real Claude
Code session, and confirm: activity glyph/label/timer track the session; the
usage readout shows real percentages; the popup lists the session and usage bars;
the config toggle hides/shows the readout.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(printf 'Update: add README and finalize MVP\n\nDocument requirements, install/uninstall, what the panel and popup show,\nand the usage-endpoint caveat. Full pytest suite green.\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
```

---

## Self-Review Notes

- **Spec coverage:** activity states + timer (T2/T3/T5); multi-session priority (T3); panel usage % right-aligned (T6); config toggle (T7); popup sessions + usage bars (T8); auto-merge install (T9); Step-0 spike gate (T0); testing strategy (tests in T1–T4, T9; manual QML in T5/T6/T7/T8/T10). All spec sections mapped.
- **Type consistency:** aggregate keys (`state`, `tool`, `started_at`, `active_count`, `waiting_count`, `sessions`) and usage keys (`status`, `five_hour`, `seven_day`, each `{utilization}`) are used identically in scripts and QML. Config key `showUsageOnPanel` consistent across main.xml, main.qml, CompactView.qml.
- **Path resolution:** `main.qml` builds commands from `binDir` containing a literal `${XDG_DATA_HOME:-$HOME/.local/share}`; the executable engine runs via `/bin/sh`, which expands it. If a future Plasma version stops using a shell, replace `binDir` with a hardcoded `~/.local/share/claude-status-bar/bin` (the path the installer always uses). Flagged for the implementer.
- **Usage keys:** confirmed by the Task 0 spike; if the real JSON differs, update `build_result` (T4) and `pct()`/`part()` readers (T6/T8) together.
