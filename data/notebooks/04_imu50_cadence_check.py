# Databricks notebook source
# MAGIC %md
# MAGIC # 04 IMU50: do Gummi's cadence bands track wrist activity? (decision D-19)
# MAGIC Reads a few IMU50 subjects straight out of the 46.7 GB Zenodo zip with HTTP range requests (about 150 MB per
# MAGIC subject per 12 hours, never the full archive), estimates walking cadence per minute from the wrist accelerometer, and
# MAGIC compares minutes in Gummi's bands (light 1-99, moderate 100-129, vigorous 130+ steps/min, Tudor-Locke 2019)
# MAGIC with the ActiGraph's hourly METs. Writes `gummi_data.imu50_minutes` and `gummi_data.imu50_hourly_check`, logs
# MAGIC the summary to MLflow. The cadence estimate is a heuristic (dominant periodicity of the wrist signal), so the
# MAGIC claim is limited to: hours with more moderate-or-faster minutes carry higher METs.

# COMMAND ----------

dbutils.widgets.text("catalog", "")
dbutils.widgets.text("subjects", "00,05,13,20,44")
dbutils.widgets.text("hours", "24")
catalog = dbutils.widgets.get("catalog").strip()
subjects = [s.strip().zfill(2) for s in dbutils.widgets.get("subjects").split(",") if s.strip()]
hours = float(dbutils.widgets.get("hours"))
assert catalog, "Set the catalog widget (decision D-07)."

import json, os, sys, time
nb_path = dbutils.notebook.entry_point.getDbutils().notebook().getContext().notebookPath().get()
data_root = os.path.dirname(os.path.dirname("/Workspace" + nb_path))
if data_root not in sys.path:
    sys.path.insert(0, data_root)
import pandas as pd
from imu50 import hourly_check, subject_minutes

# COMMAND ----------

from concurrent.futures import ThreadPoolExecutor, as_completed

frames, scores, read_mb, failed = [], [], {}, {}
t0 = time.time()
with ThreadPoolExecutor(max_workers=len(subjects)) as pool:          # Zenodo serves each stream slowly; read in parallel
    futures = {pool.submit(subject_minutes, s, hours): s for s in subjects}
    for fut in as_completed(futures):
        s = futures[fut]
        try:
            m, sc, mb = fut.result()
        except Exception as exc:                                     # one bad subject does not sink the rest
            failed[s] = f"{exc.__class__.__name__}: {str(exc)[:200]}"
            print(f"subject {s} FAILED: {failed[s]}")
            continue
        frames.append(m); scores.append(sc); read_mb[s] = mb
        print(f"subject {s}: {len(m)} minutes, {int(m['walking'].sum())} walking-like, {mb} MB read, {time.time() - t0:.0f}s")
assert frames, f"every subject failed: {failed}"
minutes = pd.concat(frames, ignore_index=True)
scoring = pd.concat(scores, ignore_index=True)
hourly, summary = hourly_check(minutes, scoring)
summary.update({"hours_per_subject": hours, "mb_read": read_mb, "failed": failed, "seconds": round(time.time() - t0)})
print(json.dumps(summary, indent=1, default=str))

# COMMAND ----------

def save(df, table, comment):
    full = f"`{catalog}`.gummi_data.{table}"
    spark.createDataFrame(df).write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(full)
    spark.sql(f"COMMENT ON TABLE {full} IS '{comment}'")
    return spark.table(full).count()

counts = {
    "imu50_minutes": save(minutes, "imu50_minutes", "IMU50 wrist accelerometer: per-minute cadence estimate and walking flag (D-19 check)"),
    "imu50_hourly_check": save(hourly, "imu50_hourly_check", "IMU50: minutes per Gummi cadence band per hour next to ActiGraph hourly METs"),
}

import mlflow
mlflow.set_experiment("/Shared/gummi_model")
with mlflow.start_run(run_name="imu50_cadence_check") as run:
    mlflow.log_params({"subjects": ",".join(subjects), "hours_per_subject": hours})
    if summary["spearman_moderate_plus_minutes_vs_METs"] is not None:
        mlflow.log_metric("spearman_moderate_plus_minutes_vs_METs", summary["spearman_moderate_plus_minutes_vs_METs"])
    mlflow.log_dict(summary, "imu50_summary.json")
summary.update({"tables": counts, "mlflow_run_id": run.info.run_id})
dbutils.notebook.exit(json.dumps(summary, default=str))
