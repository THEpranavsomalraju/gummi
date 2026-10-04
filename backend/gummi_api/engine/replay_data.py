"""Replay tables (Data's workspace.gummi_data.replay_cgm and replay_meals): read once through the SQL warehouse,
cached as parquet so a restart does not wait on the warehouse."""
import logging
from pathlib import Path

import pandas as pd

from .. import config

log = logging.getLogger("gummi.replay")
CGM_COLS = ["user_id", "t_offset_min", "glucose_mg_dl"]
MEAL_COLS = ["user_id", "meal_id", "t_offset_min", "items", "carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g",
             "calories", "is_standard_breakfast"]


def _sql(statement: str) -> pd.DataFrame:
    from databricks.sdk import WorkspaceClient
    from databricks.sdk.service.sql import Disposition, Format
    w = WorkspaceClient()
    r = w.statement_execution.execute_statement(warehouse_id=config.WAREHOUSE_ID, statement=statement,
                                                wait_timeout="50s", disposition=Disposition.INLINE,
                                                format=Format.JSON_ARRAY)
    while r.status.state.value in ("PENDING", "RUNNING"):
        r = w.statement_execution.get_statement(r.statement_id)
    if r.status.error:
        raise RuntimeError(r.status.error.message)
    cols = [c.name for c in r.manifest.schema.columns]
    rows = list(r.result.data_array or [])
    chunk = r.result
    while chunk.next_chunk_index is not None:
        chunk = w.statement_execution.get_statement_result_chunk_n(r.statement_id, chunk.next_chunk_index)
        rows.extend(chunk.data_array or [])
    return pd.DataFrame(rows, columns=cols)


def _typed(cgm: pd.DataFrame, meals: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    cgm = cgm[CGM_COLS].astype({"t_offset_min": float, "glucose_mg_dl": float})
    meals = meals[MEAL_COLS].copy()
    for c in ("t_offset_min", "carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g", "calories"):
        meals[c] = pd.to_numeric(meals[c], errors="coerce")
    meals["is_standard_breakfast"] = meals["is_standard_breakfast"].astype(str).str.lower() == "true"
    keep = set(config.PARTICIPANTS)
    return (cgm[cgm.user_id.isin(keep)].sort_values(["user_id", "t_offset_min"]).reset_index(drop=True),
            meals[meals.user_id.isin(keep)].sort_values(["user_id", "t_offset_min"]).reset_index(drop=True))


def load_replay() -> tuple[pd.DataFrame, pd.DataFrame]:
    src = config.REPLAY_SOURCE
    cache = config.CACHE_DIR
    if src == "cache":
        return pd.read_parquet(cache / "replay_cgm.parquet"), pd.read_parquet(cache / "replay_meals.parquet")
    if src != "sql":
        folder = Path(src)
        return _typed(pd.read_csv(folder / "replay_cgm.csv"), pd.read_csv(folder / "replay_meals.csv"))
    try:
        t = f"{config.CATALOG}.gummi_data"
        cgm = _sql(f"SELECT {', '.join(CGM_COLS)} FROM {t}.replay_cgm")
        meals = _sql(f"SELECT {', '.join(MEAL_COLS)} FROM {t}.replay_meals")
        cgm, meals = _typed(cgm, meals)
        cache.mkdir(parents=True, exist_ok=True)
        cgm.to_parquet(cache / "replay_cgm.parquet")
        meals.to_parquet(cache / "replay_meals.parquet")
        log.info("replay tables from the warehouse: %d readings, %d meals", len(cgm), len(meals))
        return cgm, meals
    except Exception as e:  # noqa: BLE001
        if (cache / "replay_cgm.parquet").exists():
            log.warning("warehouse read failed (%s); using cached replay tables", e)
            return pd.read_parquet(cache / "replay_cgm.parquet"), pd.read_parquet(cache / "replay_meals.parquet")
        raise
