import importlib, os, sys
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

@pytest.fixture
def data_home(tmp_path, monkeypatch):
    """Redirect XDG_DATA_HOME so tests never touch the real data dir."""
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    import statusbar_paths
    importlib.reload(statusbar_paths)
    statusbar_paths.ensure_dirs()
    return tmp_path
