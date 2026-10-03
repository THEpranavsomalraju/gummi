# Databricks notebook source
# MAGIC %md
# MAGIC # 03 Streaming spike (decision D-21)
# MAGIC One command runs all three steps as the job `gummi_stream_spike`:
# MAGIC `databricks bundle run gummi_stream_spike --var="catalog=<CATALOG>" --profile gummi`
# MAGIC 1. `mode=land`: copies the sample StreamEvent files from `data/pipelines/gummi_stream/sample_events/` (made by
# MAGIC    `data/scripts/make_test_events.py` from real replay data and real gummi_model calls) into the landing volume,
# MAGIC    renamed `<run_stamp>_<source>_<seq>.jsonl` so Auto Loader sees new files.
# MAGIC 2. The job's pipeline task runs one triggered update of `gummi_stream`. By hand: start the pipeline in the UI.
# MAGIC 3. `mode=check`: rows for this run against `EXPECTED.json`, file-to-table lag (`landed_at` to `ingested_at`),
# MAGIC    and gold accuracy. Raises if this run's events did not all arrive.
# MAGIC Continuous mode (D-21): deploy with `--var="continuous=true"`, start the pipeline, run `mode=land`, wait a
# MAGIC minute, run `mode=check` with the printed run stamp. Continuous lag is the number to record.

# COMMAND ----------

dbutils.widgets.text("catalog", "")
dbutils.widgets.dropdown("mode", "land", ["land", "check"])
dbutils.widgets.text("run_stamp", "")
catalog = dbutils.widgets.get("catalog").strip()
mode = dbutils.widgets.get("mode")
assert catalog, "Set the catalog widget (decision D-07)."

import datetime
import json
import os
import shutil

nb_path = dbutils.notebook.entry_point.getDbutils().notebook().getContext().notebookPath().get()
data_root = os.path.dirname(os.path.dirname("/Workspace" + nb_path))
src = os.path.join(data_root, "pipelines", "gummi_stream", "sample_events")
dst = f"/Volumes/{catalog}/gummi_data/landing/events"
expected = json.load(open(os.path.join(src, "EXPECTED.json")))

# COMMAND ----------

if mode == "land":
    os.makedirs(dst, exist_ok=True)
    landed_at = datetime.datetime.now(datetime.timezone.utc)
    run_stamp = landed_at.strftime("%Y%m%dT%H%M%S")
    files = sorted(f for f in os.listdir(src) if f.endswith(".jsonl"))
    for i, f in enumerate(files):
        source = f.split("_")[1]                      # <YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl
        shutil.copy(os.path.join(src, f), os.path.join(dst, f"{run_stamp}_{source}_{i + 1:04d}.jsonl"))
    try:
        dbutils.jobs.taskValues.set(key="run_stamp", value=run_stamp)
    except Exception:
        pass
    print(f"landed {len(files)} files ({expected['events']} events) at {landed_at.isoformat()}")
    print(f"run stamp: {run_stamp}  (use it for mode=check if you run by hand)")
    dbutils.notebook.exit(run_stamp)

# COMMAND ----------

from pyspark.sql import functions as F

run_stamp = dbutils.widgets.get("run_stamp").strip()
if not run_stamp:
    try:
        run_stamp = dbutils.jobs.taskValues.get(taskKey="land", key="run_stamp", debugValue="")
    except Exception:
        run_stamp = ""
bronze_all = spark.table(f"`{catalog}`.gummi_data.stream_bronze_events")
if not run_stamp:
    run_stamp = (bronze_all.select(F.regexp_extract("source_file", r"/(\d{8}T\d{6})_[a-z_]+_\d{4}\.jsonl$", 1).alias("s"))
                 .where("s != ''").agg(F.max("s")).first()[0])
print("checking run stamp", run_stamp)
bronze = bronze_all.where(F.col("source_file").contains(f"/{run_stamp}_"))

got = {r["kind"]: r["count"] for r in bronze.groupBy("kind").count().collect()}
missing = []
print("this run, bronze rows by kind (got / expected):")
for kind, n in sorted(expected["by_kind"].items()):
    print(f"  {kind:<11} {got.get(kind, 0):>5} / {n}")
    if got.get(kind, 0) < n:
        missing.append(kind)
print("all tables (cumulative across runs):")
for t in ["stream_bronze_events", "stream_silver_cgm", "stream_silver_meals", "stream_silver_predictions",
          "stream_silver_grades", "stream_silver_cards", "stream_gold_fleet", "stream_gold_accuracy"]:
    try:
        print(f"  {t:<26} {spark.table(f'`{catalog}`.gummi_data.{t}').count()}")
    except Exception as exc:
        print(f"  {t:<26} missing: {exc.__class__.__name__}")

# COMMAND ----------

# MAGIC %md Lag for D-21: seconds from file landing to pipeline ingestion, this run only. In triggered mode the lag
# MAGIC includes waiting for the update to start; continuous mode shows the steady-state lag.

# COMMAND ----------

lag = bronze.select((F.unix_timestamp("ingested_at") - F.unix_timestamp("landed_at")).alias("lag"))
row = lag.agg(F.min("lag").alias("min"), F.expr("percentile(lag, 0.5)").alias("median"), F.max("lag").alias("max")).first()
print(f"lag seconds: min {row['min']}, median {row['median']}, max {row['max']}")
display(bronze.groupBy("source_file").agg(F.min("landed_at").alias("landed_at"), F.min("ingested_at").alias("ingested_at"),
                                          F.count("*").alias("events")).orderBy("source_file").limit(20))

# COMMAND ----------

# MAGIC %md Gold accuracy should match `EXPECTED.json` when the tables hold only sample events (rows are deduplicated by
# MAGIC id, so re-runs give the same numbers; Backend mock events in the same tables change them).

# COMMAND ----------

gold = spark.table(f"`{catalog}`.gummi_data.stream_gold_accuracy").where("user_id = 'ALL'").toPandas()
cols = ["sample", "window_type", "grades", "gummi_mae_mg_dl", "cgm_only_mae_mg_dl", "last_value_mae_mg_dl",
        "gummi_beats_cgm_only_pct", "gummi_beats_last_value_pct"]
print(gold[cols].sort_values(["sample", "window_type"]).to_string(index=False))
print("expected from the sample alone:")
for r in expected["expected_gold_accuracy"]:
    if r["user_id"] == "ALL":
        print(" ", r)
if missing:
    raise AssertionError(f"events missing for kinds {missing} (run stamp {run_stamp}); check the pipeline event log")
print("PASS: every event of this run reached stream_bronze_events")
dbutils.notebook.exit(json.dumps({
    "run_stamp": run_stamp, "bronze_by_kind": got, "expected_by_kind": expected["by_kind"],
    "lag_seconds": {"min": row["min"], "median": row["median"], "max": row["max"]},
    "gold_accuracy_all": gold.to_dict(orient="records"), "pass": True}, default=str))
