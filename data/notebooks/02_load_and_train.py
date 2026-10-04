# Databricks notebook source
# MAGIC %md
# MAGIC # 02 Load BIG IDEAs, evaluate, train and register gummi_model
# MAGIC Reads `/Volumes/<catalog>/gummi_data/raw_bigideas/bigideas_1.1.3/` (uploaded with route B), writes the
# MAGIC bronze, silver and replay tables, runs the same code as `data/scripts/run_local_pipeline.py`
# MAGIC (published-baseline reproduction, participant-grouped evaluation, meal and HR ablations, meal-prediction
# MAGIC evaluation), writes `gummi_ml` tables, logs everything to MLflow, registers `<catalog>.gummi_ml.gummi_model`,
# MAGIC and copies the artifact to `/Volumes/<catalog>/gummi_ml/artifacts/<config.VERSION>/` for the App (D-05).
# MAGIC Expected runtime: 5 to 10 minutes on serverless. Numbers stay DRAFT until the human approves them.

# COMMAND ----------

dbutils.widgets.text("catalog", "")
dbutils.widgets.text("exclude", "015")
catalog = dbutils.widgets.get("catalog").strip()
exclude = tuple(x.strip() for x in dbutils.widgets.get("exclude").split(",") if x.strip())
assert catalog, "Set the catalog widget (decision D-07)."
raw = f"/Volumes/{catalog}/gummi_data/raw_bigideas/bigideas_1.1.3"

# COMMAND ----------

import os, sys
nb_path = dbutils.notebook.entry_point.getDbutils().notebook().getContext().notebookPath().get()
data_root = os.path.dirname(os.path.dirname("/Workspace" + nb_path))   # .../files (bundle root = gummi/data)
if data_root not in sys.path:
    sys.path.insert(0, data_root)
print("code from", data_root)

import pandas as pd
import gummi_pipeline
from bigideas.bronze import bronze_cgm, bronze_demographics, bronze_food_log, bronze_hr

# COMMAND ----------

written = {}

def save(df: pd.DataFrame, table: str, comment: str = ""):
    df = df.copy()
    for c in df.columns:
        if df[c].dtype == object:
            df[c] = df[c].astype("string")
    sdf = spark.createDataFrame(df)
    full = f"`{catalog}`.{table}"
    sdf.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(full)
    if comment:
        safe = comment.replace("\\", "\\\\").replace("'", "\\'")     # escape for a SQL string literal
        spark.sql(f"COMMENT ON TABLE {full} IS '{safe}'")
    written[table] = spark.table(full).count()
    print(f"{full}: {written[table]} rows")

save(bronze_cgm(raw), "gummi_data.bronze_cgm", "Raw Dexcom export rows (metadata, alerts and EGV), strings, plus participant_id")
save(bronze_food_log(raw), "gummi_data.bronze_food_log", "Raw food log rows mapped to 14 standard columns; source_layout records the original layout")
save(bronze_demographics(raw), "gummi_data.bronze_demographics", "Demographics.csv as delivered")
hr = bronze_hr(raw)
if hr is not None:
    save(hr, "gummi_data.bronze_hr", "Per-minute mean heart rate from the 1 Hz E4 file (ablation only)")

# COMMAND ----------

out = "/tmp/gummi_out"
res = gummi_pipeline.run(raw, out, exclude=exclude, use_hr=hr is not None, meal_eval=True)

# COMMAND ----------

tables = {
    "gummi_data.silver_cgm_5min": ("silver_cgm_5min", "CGM master clock: EGV readings, islands split at gaps over 15 minutes"),
    "gummi_data.silver_meals": ("silver_meals", "Food log rows within 15 minutes grouped into meals, macro totals, standardized breakfast flag"),
    "gummi_data.replay_cgm": ("replay_cgm", "Replay CGM: minutes from each participant's first local midnight"),
    "gummi_data.replay_meals": ("replay_meals", "Replay meals: minutes from each participant's first local midnight"),
    "gummi_ml.eval_results": ("eval_results", "Participant-grouped evaluation: Gummi vs mean, persistence, CGM-only linear regression, by horizon and window type (DRAFT)"),
    "gummi_ml.ablation_results": ("ablation_results", "Meal ablation: CGM only vs CGM plus meals, per horizon and window, fold spread (DRAFT)"),
    "gummi_ml.breakfast_response": ("breakfast_response", "Standardized breakfast rises per participant"),
    "gummi_ml.meal_prediction_eval": ("meal_predictions", "Per held-out meal: Gummi predicted peak and curve error vs the last-value guess (DRAFT)"),
    "gummi_ml.meal_prediction_summary": ("meal_prediction_summary", "Meal-time predictions summarized: peak and curve error, Gummi vs CGM-only vs last-value guess (DRAFT)"),
    "gummi_ml.baseline_repro": ("baseline_per_fold", "Published CGM-only baseline reproduction, per fold"),
    "gummi_ml.personal_layer_eval": ("personal_layer_eval", "Per held-out meal: prediction with no personal layer, a personal carb factor, or factor plus offset, learned online from earlier meals (DRAFT)"),
    "gummi_ml.personal_layer_summary": ("personal_layer_summary", "Personal layer summary by variant (DRAFT)"),
    "gummi_ml.completeness": ("completeness", "CGM completeness per participant (D-20 evidence)"),
}
for table, (key, comment) in tables.items():
    if key in res:
        save(res[key], table, comment)
if "ablation_hr" in res:
    save(res["ablation_hr"], "gummi_ml.ablation_hr", "Heart-rate ablation: CGM plus meals vs plus HR (DRAFT)")

# COMMAND ----------

import json, shutil
import mlflow
from mlflow.models import infer_signature
from gummi_model.mlflow_pyfunc import GummiPyfunc

mlflow.set_registry_uri("databricks-uc")
mlflow.set_experiment("/Shared/gummi_model")      # one shared experiment the whole team can open
art = str(res["artifact_dir"])
er = res["eval_results"]
example_req = json.dumps({"method": "forecast", "user_id": "p_012", "now": "2026-10-04T09:00:00+00:00", "minutes": 30,
                          "cgm": [{"t": f"2026-10-04T0{h}:{m:02d}:00+00:00", "glucose_mg_dl": 100 + m / 5}
                                  for h in (6, 7) for m in range(0, 60, 5)],
                          "meals": [{"eaten_at": "2026-10-04T07:30:00+00:00", "carbs_g": 50}]})
from gummi_model import config as C
with mlflow.start_run(run_name=C.VERSION) as run:
    mlflow.log_params({"feature_set": res["feature_set"], "simulate_method": res["simulate_method"],
                       "excluded": ",".join(exclude), "participants": len(res["silver_cgm_5min"].participant_id.unique())})
    for _, r in er[er.window == "all"].iterrows():
        mlflow.log_metric(f"rmse_{r.model}_{int(r.horizon_min)}min", float(r.rmse_mean))
    for f in os.listdir(out):
        if f.endswith(".csv") or f.endswith(".json"):
            mlflow.log_artifact(os.path.join(out, f), artifact_path="reports")
    py = GummiPyfunc()
    py.load_context(type("Ctx", (), {"artifacts": {"gummi_model": art}})())
    example_out = py.predict(None, pd.DataFrame({"request": [example_req]}))
    info = mlflow.pyfunc.log_model(
        artifact_path="gummi_model", python_model=GummiPyfunc(), artifacts={"gummi_model": art},
        code_paths=[os.path.join(data_root, "gummi_model")],
        signature=infer_signature(pd.DataFrame({"request": [example_req]}), example_out),
        pip_requirements=["numpy", "pandas"],
        registered_model_name=f"{catalog}.gummi_ml.gummi_model",
    )
    print("MLflow run", run.info.run_id)

dest = f"/Volumes/{catalog}/gummi_ml/artifacts/{C.VERSION}"   # a new version gets its own folder; older ones stay
shutil.rmtree(dest, ignore_errors=True)
shutil.copytree(art, dest)
print("artifact for the App:", dest, os.listdir(dest))

base = res["baseline_summary"].set_index("model")["rmse_mean"].to_dict() if "baseline_summary" in res else {}
dbutils.notebook.exit(json.dumps({
    "tables": written, "mlflow_run_id": run.info.run_id, "experiment": "/Shared/gummi_model",
    "registered_model": f"{catalog}.gummi_ml.gummi_model",
    "registered_version": getattr(info, "registered_model_version", None), "artifact": dest,
    "feature_set": res["feature_set"], "simulate_method": res["simulate_method"],
    "baseline_30min_rmse": base,
}, default=str))
