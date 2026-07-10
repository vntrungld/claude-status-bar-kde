#!/usr/bin/env python3
"""Merge all per-session status files into one aggregate JSON line on stdout."""
import glob, json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

STALE_SECS = 900

def _num(v, default=0):
    """Coerce a value to int safely, returning default on type/value error."""
    try:
        return int(v)
    except (TypeError, ValueError):
        return default

def aggregate(docs, now):
    live = [x for x in docs
            if not (x.get("state") != "idle"
                    and now - _num(x.get("updated_at"), 0) > STALE_SECS)]
    active = [x for x in live if x.get("state") in ("thinking", "tool", "waiting")]
    waiting = [x for x in active if x["state"] == "waiting"]
    tools = [x for x in active if x["state"] == "tool"]

    if waiting:
        state, tool = "waiting", None
    elif tools:
        state = "tool"
        tool = max(tools, key=lambda x: _num(x.get("updated_at"), 0)).get("tool")
    elif active:
        state, tool = "thinking", None
    else:
        state, tool = "idle", None

    starts = [_num(x["started_at"]) for x in active if _num(x.get("started_at"), 0) > 0]
    started_at = min(starts) if starts else None

    return {"state": state, "tool": tool, "started_at": started_at,
            "active_count": len(active), "waiting_count": len(waiting),
            "sessions": live}

def load_docs():
    import statusbar_paths as p
    docs = []
    for f in glob.glob(os.path.join(p.sessions_dir(), "*.json")):
        try:
            with open(f) as fh:
                docs.append(json.load(fh))
        except (OSError, ValueError):
            continue
    return docs

if __name__ == "__main__":
    print(json.dumps(aggregate(load_docs(), int(time.time()))))
