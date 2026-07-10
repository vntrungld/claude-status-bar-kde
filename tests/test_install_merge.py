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

def test_unmerge_removes_our_hooks_only():
    m = _mod()
    s = m.merge({}, "/data/bin")
    m.unmerge(s, "/data/bin")
    assert s["hooks"] == {}  # all our events removed, nothing else present

def test_unmerge_preserves_foreign_hook_in_same_group():
    m = _mod()
    cmd = m.hook_command("/data/bin", "PreToolUse")
    s = {"hooks": {"PreToolUse": [
        {"matcher": "*", "hooks": [
            {"type": "command", "command": "other.sh"},
            {"type": "command", "command": cmd}]}]}}
    m.unmerge(s, "/data/bin")
    cmds = [h["command"] for g in s["hooks"]["PreToolUse"] for h in g["hooks"]]
    assert cmds == ["other.sh"]  # foreign kept, ours gone, group NOT dropped

def test_unmerge_preserves_foreign_hook_in_separate_group():
    m = _mod()
    s = m.merge({"hooks": {"Stop": [
        {"matcher": "*", "hooks": [{"type": "command", "command": "keep.sh"}]}]}}, "/data/bin")
    m.unmerge(s, "/data/bin")
    cmds = [h["command"] for g in s["hooks"]["Stop"] for h in g["hooks"]]
    assert cmds == ["keep.sh"]

def test_unmerge_is_idempotent():
    m = _mod()
    s = m.merge({}, "/data/bin")
    m.unmerge(s, "/data/bin")
    m.unmerge(s, "/data/bin")  # second call must not crash
    assert s["hooks"] == {}
