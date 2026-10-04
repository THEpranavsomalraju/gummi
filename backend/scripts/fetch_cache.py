"""Fill backend/.cache with the model artifact and the replay tables (for tests and offline runs).

    DATABRICKS_CONFIG_PROFILE=gummi .venv/bin/python scripts/fetch_cache.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from gummi_api import config  # noqa: E402
from gummi_api.engine.model_adapter import _download  # noqa: E402
from gummi_api.engine.replay_data import load_replay  # noqa: E402

_download(config.MODEL_VOLUME_DIR if config.MODEL_VOLUME_DIR.startswith("/Volumes") else
          f"/Volumes/{config.CATALOG}/gummi_ml/artifacts/gummi_model_v1", config.CACHE_DIR / "gummi_model_v1")
cgm, meals = load_replay()
print(f"cache ready in {config.CACHE_DIR}: model, {len(cgm)} readings, {len(meals)} meals")
