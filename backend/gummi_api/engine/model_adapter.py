"""Load gummi_model once (full model, 5 fold models, participant-to-fold map) from the Unity Catalog volume (D-34)."""
import logging
import shutil
from pathlib import Path

from .. import config

log = logging.getLogger("gummi.model")
FILES = ("model.npz", "meta.json")


def _download(volume_dir: str, dest: Path) -> Path:
    from databricks.sdk import WorkspaceClient
    w = WorkspaceClient()
    dest.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        resp = w.files.download(f"{volume_dir}/{name}")
        with open(dest / name, "wb") as f:
            shutil.copyfileobj(resp.contents, f)
    return dest


def load_model():
    """Local folder if GUMMI_MODEL_DIR points at one, else download the volume copy into the cache."""
    from gummi_model import GlucoseModel
    src = Path(config.MODEL_VOLUME_DIR)
    if src.is_dir() and all((src / f).exists() for f in FILES):
        path = src                                   # local dir, or /Volumes FUSE mount when it exists
    else:
        path = config.CACHE_DIR / "gummi_model_v1"
        try:
            _download(config.MODEL_VOLUME_DIR, path)
        except Exception as e:  # noqa: BLE001
            if not all((path / f).exists() for f in FILES):
                raise
            log.warning("model download failed (%s); using cached copy", e)
    model = GlucoseModel.load(path)
    log.info("loaded %s from %s", model.version, path)
    return model
