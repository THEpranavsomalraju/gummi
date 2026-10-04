"""Background refresher for the gold tables (D-34): /fleet and get_gold_summary read this cache, never the warehouse.

Queries run every GOLD_REFRESH_SECONDS while the replay runs (and once at startup), so the warehouse can idle and
stop between demos instead of burning Free Edition quota.
"""
import asyncio
import logging
from datetime import datetime, timezone

from .. import config
from ..stream.producer import clock

log = logging.getLogger("gummi.gold")
T = f"{config.CATALOG}.gummi_data"
NUM = ("grades", "gummi_mae_mg_dl", "cgm_only_mae_mg_dl", "last_value_mae_mg_dl", "gummi_beats_cgm_only_pct",
       "gummi_beats_last_value_pct", "gummi_peak_error_mg_dl", "within_band_pct")


class Gold:
    def __init__(self):
        self.by_user: dict[str, dict] = {}
        self.rollup: dict | None = None
        self.rows: list[dict] = []                 # every gold accuracy row (all samples and window types)
        self.pipeline_lag_seconds: float | None = None
        self.refreshed_at: str | None = None
        self.last_error: str | None = None

    def _query(self, sql: str) -> list[dict]:
        from databricks.sdk import WorkspaceClient
        w = WorkspaceClient()
        r = w.statement_execution.execute_statement(warehouse_id=config.WAREHOUSE_ID, statement=sql, wait_timeout="30s")
        if r.status.error:
            raise RuntimeError(r.status.error.message)
        cols = [c.name for c in r.manifest.schema.columns]
        return [dict(zip(cols, row)) for row in (r.result.data_array or [])]

    def refresh(self) -> None:
        rows = self._query(f"SELECT * FROM {T}.stream_gold_accuracy")
        for row in rows:
            for k in NUM:
                if row.get(k) is not None:
                    row[k] = round(float(row[k]), 1)
        self.rows = rows
        oos = [r for r in rows if r.get("sample") == "out-of-sample" and r.get("window_type") == "all"]
        self.by_user = {r["user_id"]: r for r in oos if r["user_id"] != "ALL"}
        self.rollup = next((r for r in oos if r["user_id"] == "ALL"), None)
        lag = self._query(f"SELECT max(to_timestamp(released_at)) AS newest FROM {T}.stream_bronze_events")
        newest = lag[0]["newest"] if lag else None
        if newest and clock.running:
            ts = datetime.fromisoformat(str(newest).replace("Z", "+00:00").replace(" ", "T"))
            ts = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
            self.pipeline_lag_seconds = round(max(0.0, (datetime.now(timezone.utc) - ts).total_seconds()), 1)
        self.refreshed_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        self.last_error = None

    def summary(self, user_id: str) -> list[dict]:
        """get_gold_summary: the user's rows plus the out-of-sample ALL rollup."""
        return [r for r in self.rows if r.get("user_id") in (user_id, "ALL")]

    async def run(self) -> None:
        first = True
        while True:
            if first or clock.running:
                try:
                    await asyncio.to_thread(self.refresh)
                except Exception as e:  # noqa: BLE001
                    self.last_error = f"{type(e).__name__}: {str(e)[:200]}"
                    log.warning("gold refresh failed: %s", self.last_error)
                first = False
            await asyncio.sleep(config.GOLD_REFRESH_SECONDS)

    def status(self) -> dict:
        return {"refreshed_at": self.refreshed_at, "users": len(self.by_user), "rollup": self.rollup,
                "pipeline_lag_seconds": self.pipeline_lag_seconds, "last_error": self.last_error}


gold = Gold()
