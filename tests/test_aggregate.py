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
