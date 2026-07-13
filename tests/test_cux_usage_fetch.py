import importlib.util, json, os

CF = os.path.join(os.path.dirname(__file__), "..", "scripts", "cux-usage-fetch.py")

def _mod():
    spec = importlib.util.spec_from_file_location("cf", CF)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

def test_cux_data_dir_honors_xdg(data_home):
    m = _mod()
    assert m.cux_data_dir() == os.path.join(str(data_home), "cux")

def test_load_state_missing_returns_none(data_home):
    m = _mod()
    assert m.load_cux_state() is None

def test_load_state_and_cache_roundtrip(data_home):
    m = _mod()
    cux = os.path.join(str(data_home), "cux")
    os.makedirs(os.path.join(cux, "runtime"), exist_ok=True)
    with open(os.path.join(cux, "state.json"), "w") as f:
        json.dump({"activeSlot": 2, "accounts": {}}, f)
    with open(os.path.join(cux, "runtime", "usage-cache.json"), "w") as f:
        json.dump({"org-1": {"five_hour": {"utilization": 5}}}, f)
    assert m.load_cux_state()["activeSlot"] == 2
    assert m.load_cux_usage_cache()["org-1"]["five_hour"]["utilization"] == 5

def test_to_epoch_nine_fractional_digits():
    m = _mod()
    # cux writes 9 fractional digits + Z; Python's fromisoformat maxes at 6.
    assert m._to_epoch("2026-07-13T05:02:52.874983408Z") == 1783918972

def test_to_epoch_no_fraction():
    m = _mod()
    assert m._to_epoch("2026-07-13T05:02:52Z") == 1783918972

def test_to_epoch_none_returns_none():
    m = _mod()
    assert m._to_epoch(None) is None
    assert m._to_epoch("") is None

def test_find_cux_binary_prefers_path(monkeypatch):
    m = _mod()
    monkeypatch.setattr(m.shutil, "which", lambda name: "/usr/bin/cux")
    assert m.find_cux_binary() == "/usr/bin/cux"
