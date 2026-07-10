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
