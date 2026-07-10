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
