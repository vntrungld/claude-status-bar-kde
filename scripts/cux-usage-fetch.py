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
