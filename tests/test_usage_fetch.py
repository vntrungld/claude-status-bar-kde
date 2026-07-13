import importlib.util, json, os

UF = os.path.join(os.path.dirname(__file__), "..", "scripts", "usage-fetch.py")

def _mod():
    spec = importlib.util.spec_from_file_location("uf", UF)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

OK_BODY = json.dumps({"five_hour": {"utilization": 42},
                      "seven_day": {"utilization": 18}})

def test_ok_response_parsed():
    m = _mod()
    out = m.build_result(now=100, http_status=200, body=OK_BODY, prev_cache=None)
    assert out["status"] == "ok"
    assert out["five_hour"]["utilization"] == 42
    assert out["seven_day"]["utilization"] == 18
    assert out["fetched_at"] == 100

def test_429_keeps_prev_values():
    m = _mod()
    prev = {"status": "ok", "fetched_at": 1, "five_hour": {"utilization": 40},
            "seven_day": {"utilization": 10}}
    out = m.build_result(now=200, http_status=429, body="", prev_cache=prev)
    assert out["status"] == "rate_limited"
    assert out["five_hour"]["utilization"] == 40  # preserved

def test_401_is_reauth():
    m = _mod()
    out = m.build_result(now=1, http_status=401, body="", prev_cache=None)
    assert out["status"] == "reauth"

def test_error_status_without_prev():
    m = _mod()
    out = m.build_result(now=1, http_status=500, body="", prev_cache=None)
    assert out["status"] == "error"

def test_load_prev_cache_missing_returns_none(data_home):
    m = _mod()
    assert m.load_prev_cache() is None  # no cache file yet

def test_read_token_missing_file_returns_none(tmp_path):
    m = _mod()
    m.CRED = str(tmp_path / "nonexistent.json")
    assert m.read_token() == (None, None)

def test_main_missing_credentials_prints_reauth(tmp_path, capsys, data_home):
    m = _mod()
    m.CRED = str(tmp_path / "nonexistent.json")
    m.main()
    out = json.loads(capsys.readouterr().out.strip())
    assert out["status"] == "reauth"

def test_compute_returns_dict_and_writes_cache(tmp_path, data_home):
    import statusbar_paths as p
    m = _mod()
    m.CRED = str(tmp_path / "nonexistent.json")  # forces reauth path
    out = m.compute()
    assert out["status"] == "reauth"
    # reauth is not rate_limited, so the cache is written
    assert os.path.exists(p.usage_cache_path())
