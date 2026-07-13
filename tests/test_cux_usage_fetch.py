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


def _state():
    return {
        "activeSlot": 2,
        "accounts": {
            "1": {"slot": 1, "email": "oe@x.com", "alias": "oe", "orgUuid": "org-1"},
            "2": {"slot": 2, "email": "me@x.com", "alias": "", "orgUuid": "org-2"},
            "3": {"slot": 3, "email": "gone@x.com", "alias": "g", "orgUuid": "org-3"},
        },
    }

def _cache():
    return {
        "org-1": {"five_hour": {"utilization": 10}, "seven_day": {"utilization": 72},
                  "polled_at": "2026-07-13T05:02:52.874983408Z"},
        "org-2": {"five_hour": {"utilization": 41}, "seven_day": {"utilization": 14},
                  "polled_at": "2026-07-13T05:02:53.136051313Z"},
        # org-3 intentionally absent from cache (never polled)
    }

def test_build_multi_orders_by_slot_and_flags_active():
    m = _mod()
    r = m.build_multi(_state(), _cache(), now=1752383800)
    assert r["multi"] is True
    slots = [a["slot"] for a in r["accounts"]]
    assert slots == [1, 2, 3]
    active = [a for a in r["accounts"] if a["active"]]
    assert len(active) == 1 and active[0]["slot"] == 2

def test_build_multi_top_level_is_active_account():
    m = _mod()
    r = m.build_multi(_state(), _cache(), now=1752383800)
    assert r["five_hour"]["utilization"] == 41   # slot 2 (active)
    assert r["seven_day"]["utilization"] == 14
    assert r["status"] == "ok"
    assert r["fetched_at"] == m._to_epoch("2026-07-13T05:02:53.136051313Z")

def test_build_multi_missing_account_marked_no_data():
    m = _mod()
    r = m.build_multi(_state(), _cache(), now=1752383800)
    g = [a for a in r["accounts"] if a["slot"] == 3][0]
    assert g["has_data"] is False
    assert g["five_hour"] == {}
    assert g["polled_at"] is None

def test_build_multi_alias_fallback_labeling_left_to_ui():
    m = _mod()
    r = m.build_multi(_state(), _cache(), now=1752383800)
    s2 = [a for a in r["accounts"] if a["slot"] == 2][0]
    assert s2["alias"] == "" and s2["email"] == "me@x.com"

def test_build_multi_empty_cache_status_loading():
    m = _mod()
    r = m.build_multi(_state(), {}, now=1752383800)
    assert r["status"] == "loading"
    assert all(a["has_data"] is False for a in r["accounts"])
    assert r["five_hour"] == {}

def test_main_no_cux_falls_back_to_single(monkeypatch, tmp_path, data_home, capsys):
    m = _mod()
    monkeypatch.setattr(m, "find_cux_binary", lambda: None)
    # Force the single-account path into its reauth branch (no creds file).
    uf = m._load_usage_fetch()
    monkeypatch.setattr(uf, "CRED", str(tmp_path / "nope.json"))
    monkeypatch.setattr(m, "_load_usage_fetch", lambda: uf)
    m.main()
    out = json.loads(capsys.readouterr().out.strip())
    assert out["multi"] is False
    assert out["status"] == "reauth"
    assert "accounts" not in out

def test_main_with_cux_builds_multi(monkeypatch, data_home, capsys):
    m = _mod()
    monkeypatch.setattr(m, "find_cux_binary", lambda: "/usr/bin/cux")
    monkeypatch.setattr(m, "run_refresh", lambda b: None)  # no real subprocess
    monkeypatch.setattr(m, "load_cux_state", _state)
    monkeypatch.setattr(m, "load_cux_usage_cache", _cache)
    m.main()
    out = json.loads(capsys.readouterr().out.strip())
    assert out["multi"] is True
    assert len(out["accounts"]) == 3
    assert out["five_hour"]["utilization"] == 41  # active (slot 2)

def test_main_cux_present_but_no_accounts_falls_back(monkeypatch, tmp_path, data_home, capsys):
    m = _mod()
    monkeypatch.setattr(m, "find_cux_binary", lambda: "/usr/bin/cux")
    monkeypatch.setattr(m, "load_cux_state", lambda: {"activeSlot": 1, "accounts": {}})
    uf = m._load_usage_fetch()
    monkeypatch.setattr(uf, "CRED", str(tmp_path / "nope.json"))
    monkeypatch.setattr(m, "_load_usage_fetch", lambda: uf)
    m.main()
    out = json.loads(capsys.readouterr().out.strip())
    assert out["multi"] is False

def test_run_refresh_swallows_subprocess_errors(monkeypatch):
    m = _mod()
    def boom(*a, **k):
        raise OSError("no such binary")
    monkeypatch.setattr(m.subprocess, "run", boom)
    m.run_refresh("/usr/bin/cux")  # must not raise
