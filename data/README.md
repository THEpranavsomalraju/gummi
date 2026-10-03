# data/ (Data Lead)

BIG IDEAs ingestion, the reproduced published baseline, gummi_model, gummi_activity, the gummi_stream streaming
pipeline, replay tables and evaluation. Rules: root `CLAUDE.md` and `data/CLAUDE.md`. Numbers in `reports/` are
DRAFT until the human approves them.

## Layout

| Path | What |
|---|---|
| `scripts/download_bigideas.py` | Download the needed BIG IDEAs v1.1.3 files with checksum checks (route B) into `raw/` (git-ignored) |
| `scripts/run_local_pipeline.py` | Whole data path on a laptop: silver tables, baseline, evaluation, ablations, training, replay tables, into `local_out/` (git-ignored) |
| `scripts/make_test_events.py` | Sample StreamEvent files for the pipeline from real replay data and real model calls |
| `scripts/setup_databricks.ps1` | Windows, HUMAN: CLI login, schemas and volumes, upload, bundle deploy, training job, streaming spike |
| `bigideas/` | Loaders for the raw files (three food-log layouts), bronze, silver, baseline, exploration, replay tables |
| `gummi_model/` | The glucose model (CONTRACT.md section 8): features, training, evaluation, grading, personal layer, walk effect, MLflow wrapper |
| `gummi_activity/` | Walk intensity from step cadence (Tudor-Locke 2019 bands) and WalkSummary |
| `gummi_pipeline.py` | The steps shared by the local script and the Databricks job |
| `pipelines/gummi_stream/` | Lakeflow Declarative Pipeline SQL (bronze, silver, gold) plus `sample_events/` and `EXPECTED.json` |
| `notebooks/` | 00 setup (schemas, volumes, library check), 02 load and train (tables, MLflow, UC registration), 03 streaming spike |
| `resources/`, `databricks.yml` | Asset Bundle: job `gummi_data_load_train`, pipeline `gummi_stream`, job `gummi_stream_spike` |
| `reports/` | Findings, evaluation, walk effect, drafts for decisions and the CONTRACT section 10 columns |
| `tests/` | pytest: loaders, no-leakage baseline, model contract and latency, activity, evaluation |

## Run it (Windows, from the repo root)

```
python -m pip install numpy pandas scikit-learn pytest
python -m pytest -q data\tests
python data\scripts\download_bigideas.py            (once, about 240 MB with the HR files)
python data\scripts\run_local_pipeline.py           (about 2 to 4 minutes, writes data\local_out\)
python data\scripts\make_test_events.py             (sample events for the pipeline)
```
Use `py` instead of `python` if that is how Python starts on your machine. The code runs unchanged on pandas 1.5
to 3.0 (Databricks serverless environments 3 to 6).

## Databricks (live since 2026-10-03)

Workspace https://dbc-0f92eb43-532a.cloud.databricks.com, catalog `workspace` (D-02, D-07). Everything below is
deployed by this folder's Asset Bundle (`databricks.yml`, target dev, no name prefixes):

| What | Where |
|---|---|
| Raw files (51, verified) | `/Volumes/workspace/gummi_data/raw_bigideas/bigideas_1.1.3/` |
| Landing for the App | `/Volumes/workspace/gummi_data/landing/events/` |
| Model for the App | `/Volumes/workspace/gummi_ml/artifacts/gummi_model_v1/`, UC model `workspace.gummi_ml.gummi_model` |
| MLflow | experiment `/Shared/gummi_model` |
| Job `gummi_data_load_train` | bronze, silver, replay and evaluation tables, training, registration (about 4 minutes) |
| Pipeline `gummi_stream` | landing to stream_bronze, silver and gold tables; triggered by default |
| Job `gummi_stream_spike` | sample events through the pipeline, checked against EXPECTED.json (D-21) |
| Job `gummi_imu50_check` | IMU50 cadence-band check (D-19) |

Redeploy and run from `data\` (Windows, CLI profile gummi):
```
databricks bundle deploy --profile gummi
databricks bundle run gummi_data_load_train --profile gummi
databricks bundle deploy --var="continuous=true" --profile gummi      (demo streaming, ~6 s lag; stop it afterward)
```
First-time setup on a new machine or workspace: `data\scripts\setup_databricks.ps1` (CLI install, login, schemas,
volumes, upload, deploy, training job, optional `-Spike`).

## For the Backend (the model in the App, decision D-05)

```python
import sys; sys.path.insert(0, "<repo>/data")       # or copy data/gummi_model and data/gummi_activity
from gummi_model import GlucoseModel, UserContext
model = GlucoseModel.load("/Volumes/<catalog>/gummi_ml/artifacts/gummi_model_v1")   # or data/local_out/gummi_model_v1
ctx = UserContext("p_004", {"timezone": "America/New_York", "high_line_mg_dl": 140.0},
                  cgm_df,      # columns t (UTC), glucose_mg_dl: confirmed readings only
                  meals_df,    # columns eaten_at (UTC), carbs_g, sugar_g, fiber_g, protein_g, fat_g
                  None, None)  # walks_df, personal (output of update_personal)
model.estimate_gap(ctx, now) + model.forecast(ctx, now, 120)   # BandPoints, about 18 ms
model.gummi_view(ctx, now)                                         # GummiView
model.simulate(ctx, now, {"carbs_g": 45, "sugar_g": 20, "fiber_g": 2, "protein_g": 5, "fat_g": 8})
```
Only numpy and pandas at run time. The profile timezone matters: time-of-day features use local time.
