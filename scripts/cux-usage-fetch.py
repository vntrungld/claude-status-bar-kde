#!/usr/bin/env python3
"""Fetch Claude usage for one or many accounts and print JSON.

When cux (multi-account wrapper) is present, refresh and join all managed
accounts into a multi-account result. Otherwise fall back to the existing
single-account fetch (usage-fetch.py). Output is a superset of usage-fetch's
shape so CompactView and the non-cux UI are unchanged.
"""
import importlib.util, json, os, re, shutil, subprocess, sys, time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def cux_data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "cux")


def find_cux_binary():
    b = shutil.which("cux")
    if b:
        return b
    cand = os.path.expanduser("~/.local/bin/cux")  # Plasma's PATH can be minimal
    return cand if os.path.exists(cand) else None


def _load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def load_cux_state():
    return _load_json(os.path.join(cux_data_dir(), "state.json"))


def load_cux_usage_cache():
    return _load_json(os.path.join(cux_data_dir(), "runtime", "usage-cache.json"))


def _to_epoch(iso):
    """Parse cux's ISO8601 (9 fractional digits + 'Z') to epoch seconds."""
    if not iso:
        return None
    s = iso.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    # fromisoformat accepts at most 6 fractional digits — truncate any extras.
    m = re.match(r"(.*\.\d{6})\d*(.*)", s)
    if m:
        s = m.group(1) + m.group(2)
    try:
        return int(datetime.fromisoformat(s).timestamp())
    except ValueError:
        return None


def build_multi(state, cache, now):
    active_slot = state.get("activeSlot")
    accounts = []
    for acc in sorted(state.get("accounts", {}).values(),
                      key=lambda a: a.get("slot", 0)):
        org = acc.get("orgUuid")
        entry = {
            "slot": acc.get("slot"),
            "alias": acc.get("alias") or "",
            "email": acc.get("email") or "",
            "active": acc.get("slot") == active_slot,
        }
        c = cache.get(org) if org else None
        if c:
            entry.update(status="ok", has_data=True,
                         five_hour=c.get("five_hour", {}),
                         seven_day=c.get("seven_day", {}),
                         polled_at=_to_epoch(c.get("polled_at")))
        else:
            entry.update(status="loading", has_data=False,
                         five_hour={}, seven_day={}, polled_at=None)
        accounts.append(entry)

    # Top level mirrors the active account (fallback: first account with data)
    # so CompactView and the popup header stay consistent with one source.
    top = next((a for a in accounts if a["active"] and a["has_data"]), None) \
        or next((a for a in accounts if a["has_data"]), None)
    return {
        "multi": True,
        "accounts": accounts,
        "status": "ok" if any(a["has_data"] for a in accounts) else "loading",
        "fetched_at": top["polled_at"] if top else None,
        "five_hour": top["five_hour"] if top else {},
        "seven_day": top["seven_day"] if top else {},
    }


def run_refresh(cux_bin):
    """Best-effort: re-poll every account. Never blocks the widget."""
    try:
        subprocess.run([cux_bin, "usage", "refresh"],
                       capture_output=True, timeout=25)
    except Exception:
        pass  # stale cache still renders below


def _load_usage_fetch():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "usage-fetch.py")
    spec = importlib.util.spec_from_file_location("usage_fetch", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fallback_single():
    result = _load_usage_fetch().compute()
    result["multi"] = False
    return result


def main():
    cux_bin = find_cux_binary()
    state = load_cux_state()
    if cux_bin and state and state.get("accounts"):
        run_refresh(cux_bin)
        cache = load_cux_usage_cache() or {}
        result = build_multi(state, cache, int(time.time()))
    else:
        result = fallback_single()
    print(json.dumps(result))


if __name__ == "__main__":
    main()
