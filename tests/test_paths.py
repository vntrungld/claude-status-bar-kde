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
