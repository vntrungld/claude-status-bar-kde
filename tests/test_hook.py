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
