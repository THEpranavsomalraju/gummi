# Databricks notebook source
# MAGIC %md
# MAGIC # 00 Setup: schemas, volumes, library check
# MAGIC Creates `gummi_data` and `gummi_ml` with the volumes in CONTRACT.md section 10 (idempotent), prints the
# MAGIC library versions for D-09, and checks outbound internet to physionet.org for the download route.
# MAGIC Set the `catalog` widget (decision D-07). Serverless compute.

# COMMAND ----------

dbutils.widgets.text("catalog", "")
catalog = dbutils.widgets.get("catalog").strip()
assert catalog, "Set the catalog widget (decision D-07)."

# COMMAND ----------

for stmt in [
    f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.gummi_data COMMENT 'Gummi: BIG IDEAs tables, replay tables, gummi_stream streaming tables'",
    f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.gummi_ml COMMENT 'Gummi: model artifacts and evaluation tables'",
    f"CREATE VOLUME IF NOT EXISTS `{catalog}`.gummi_data.raw_bigideas COMMENT 'BIG IDEAs v1.1.3 raw files (Dexcom, food logs, Demographics, HR)'",
    f"CREATE VOLUME IF NOT EXISTS `{catalog}`.gummi_data.landing COMMENT 'StreamEvent JSON lines written by the App every 5 seconds'",
    f"CREATE VOLUME IF NOT EXISTS `{catalog}`.gummi_ml.artifacts COMMENT 'gummi_model artifacts loaded by the App (D-05)'",
]:
    spark.sql(stmt)
    print("ok:", stmt.split(" COMMENT")[0])
dbutils.fs.mkdirs(f"/Volumes/{catalog}/gummi_data/landing/events")

# COMMAND ----------

# MAGIC %md ## D-09: libraries on serverless

# COMMAND ----------

import importlib
versions = {}
for lib in ["numpy", "pandas", "scipy", "sklearn", "mlflow", "pyarrow"]:
    try:
        versions[lib] = importlib.import_module(lib).__version__
    except Exception as exc:  # report, do not fail
        versions[lib] = f"MISSING ({exc.__class__.__name__})"
print(versions)

# COMMAND ----------

# MAGIC %md ## Download route check (outbound internet to physionet.org)

# COMMAND ----------

import json
import urllib.request

def reachable(url):
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "gummi-setup/1.0"})
        with urllib.request.urlopen(req, timeout=20) as r:
            return f"yes ({r.status})"
    except Exception as exc:
        return f"no ({exc.__class__.__name__}: {str(exc)[:80]})"

checks = {
    "physionet.org": reachable("https://physionet.org/files/big-ideas-glycemic-wearable/1.1.3/Demographics.csv"),
    "zenodo.org (IMU50, D-19)": reachable("https://zenodo.org/records/21468410"),
}
print(checks)
dbutils.notebook.exit(json.dumps({"versions": versions, "outbound": checks}))
