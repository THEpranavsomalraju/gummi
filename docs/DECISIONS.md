# Decisions Log

Agents append rows. Status values: DECIDED (a human chose), ASSUMED (an agent chose a reversible default, humans review), PENDING (needs a human).

## Team answers needed (humans fill these in)

| ID | Question | Answer |
|---|---|---|
| T-1 | Progress: workspace created? LinkedIn verification done? Dexcom developer app created? Xcode project on the phone? BIG IDEAs downloaded? | Workspace created and LinkedIn verification done (Nikhil, 2026-10-03). BIG IDEAs downloaded, checksums verified, uploaded to the raw volume (Data). Dexcom app: Backend. Xcode on the phone: iOS. |
| T-2 | Did organizers require using both datasets (BIG IDEAs and IMU50)? Decides whether IMU50 stays. | Not required, but the team uses IMU50 for the cadence-band check (Nikhil, 2026-10-03). See D-19 |
| T-3 | Output of `databricks serving-endpoints list --profile gummi` | Collected by the Data agent 2026-10-03, all READY. Chat: databricks-gpt-oss-120b, databricks-gpt-oss-20b, databricks-qwen3-next-80b-a3b-instruct, databricks-qwen35-122b-a10b, databricks-llama-4-maverick, databricks-gemma-3-12b, databricks-meta-llama-3-3-70b-instruct, databricks-meta-llama-3-1-8b-instruct, databricks-deepseek-v4-flash-0731. Embeddings: databricks-gte-large-en, databricks-bge-large-en, databricks-qwen3-embedding-0-6b. No Claude endpoint. D-04 is Backend's pick |
| T-4 | Real header row and first 3 lines of one Dexcom file and one food log | DONE (Data, 2026-10-03): data/reports/phase1_findings.md section 1. Dexcom: Clarity export, 12 info and alert rows, then EGV rows. Food logs: three layouts (date,time / date,time_of_day with US dates / 003 headerless 11 columns); time_begin is the eating time in all. |
| T-5 | Who holds which role, plus comfort with Swift, Spark, FastAPI | iOS Lead: Mahil (`mahilmanoharan`). Backend Lead: Pranav (`THEpranavsomalraju`). Data Lead: Nikhil (`NikhilAmbavaram`). Comfort levels: each lead adds at onboarding. |
| T-6 | Agree with the reframe: non-insulin users, coaching first, nowcast as the engine? | Yes, agreed by all three leads |

## Onboarding status

| Role | Onboarding interview | Done at |
|---|---|---|
| iOS Lead | INCOMPLETE | |
| Backend Lead | INCOMPLETE | |
| Data Lead | COMPLETE. Name (D-01), repo on data/work, Python, disk, download route B (D-38), LinkedIn done, catalog (D-07), T-2 answered. The Databricks CLI runs from the Data agent's shell with Nikhil's workspace token (git-ignored); a Windows `gummi` profile is optional | 2026-10-03 |

## Decisions

| ID | Decision | Status | Answer | By | When |
|---|---|---|---|---|---|
| D-01 | Names per role | DECIDED | iOS Lead: Mahil (`mahilmanoharan`). Backend Lead: Pranav (`THEpranavsomalraju`). Data Lead: Nikhil (`NikhilAmbavaram`). | all three leads | 2026-10-03 |
| D-02 | Workspace URL and owner | DECIDED | https://dbc-0f92eb43-532a.cloud.databricks.com, owner Nikhil (LinkedIn verification done; serverless reaches physionet.org and zenodo.org) | Nikhil | 2026-10-03 |
| D-03 | Live store | DECIDED | In-memory hot state in the App plus Delta tables through the landing volume and pipeline. No Lakebase. | team review | |
| D-04 | LLM serving endpoint (tool calling required) | PENDING | | | |
| D-05 | Model hosting | DECIDED | gummi_model runs inside the App process on CPU | team review | |
| D-06 | iPhone token type and delivery | PENDING (auth spike) | | | |
| D-07 | Unity Catalog catalog | ASSUMED | workspace: the only catalog this workspace can write to (system and samples are read-only). Schemas workspace.gummi_data and workspace.gummi_ml; the bundle defaults to it. Nikhil can still move it | Data agent | 2026-10-03 |
| D-08 | Nutrition source | DECIDED | LLM estimate plus 30 seed foods, editable portions. No USDA. | team review | |
| D-09 | Modeling libraries on serverless | DECIDED (verified) | Serverless job tasks run numpy 2.3.4, pandas 2.3.3, scipy 1.16.3, scikit-learn 1.7.2, mlflow 3.12.0, pyarrow 21.0.0 (data/notebooks/00_setup.py). No installs needed. Data code also tested on pandas 1.5.3 to 3.0.5 | Data agent | 2026-10-03 |
| D-10 | iPhone iOS version, Xcode version, minimum target | PENDING | | | |
| D-11 | Walk effect source | DECIDED | "literature" until a personal permutation test passes. Buffey et al. 2022, Sports Med 52:1765-1787, light walking vs sitting d = -0.72 (95% CI -1.03 to -0.41), times the SD of post-meal rises in BIG IDEAs (28.1 mg/dL), full effect at 10 minutes, capped at 50% of the meal's predicted effect (D-43). data/reports/walk_effect.md | Nikhil | 2026-10-03 |
| D-12 | High and low lines | ASSUMED | 140 and 70 mg/dL | docs | |
| D-13 | Bundle ID and Personal Team ID | PENDING | | | |
| D-14 | Final name | DECIDED | Gummi (project and puppet) | all three leads | 2026-10-03 |
| D-15 | Followed participant and replay day for the demo | DECIDED | p_012, replay day 6 (9 meals, standardized breakfast at 05:54, so start the replay near day6T05:00). Alternates were p_013 day 4 and p_014 day 8. data/reports/demo_day_candidates.md, data/reports/demo_day/ | Nikhil | 2026-10-03 |
| D-16 | Repo URL | DECIDED | https://github.com/mahilmanoharan/gummi (public). Branches main, ios/work, backend/work, data/work. | iOS Lead | 2026-10-03 |
| D-17 | Dexcom OAuth path | ASSUMED | Connect from the App's web page in a laptop browser, callback at <APP_URL>/api/v1/dexcom/callback. Verify in the auth spike. | docs | |
| D-18 | Dexcom sandbox user, data range, live or repeating | PENDING (expect repeating, fixed range) | | | |
| D-19 | IMU50 scope | DECIDED | Small validation of the cadence-to-intensity bands only: read 5 subjects out of the 46.7 GB Zenodo zip with HTTP range requests, never the full archive. Result: data/reports/imu50_check.md | Nikhil | 2026-10-03 |
| D-20 | BIG IDEAs participant exclusions | DECIDED | Option A: exclude 015 (user_id p_015) from training and evaluation: 75% completeness, a 21.9-hour gap, matches the published exclusion, and its food log misses its CGM dates by 14 days. Not replayed (D-37). Evidence: data/reports/phase1_findings.md section 3 | Nikhil | 2026-10-03 |
| D-21 | Pipeline mode: continuous, or triggered every minute | DECIDED (measured) | Continuous works on Free Edition serverless: events reach stream_bronze_events 4 to 8 s after landing (median 6 s), silver about 2 s later. Continuous for rehearsal, filming and judging (`databricks bundle deploy --var="continuous=true"`, start, stop afterward); triggered the rest of the time to save quota | Data agent | 2026-10-03 |
| D-22 | Replay speed, delay, start day, LLM budget for event-driven cards | ASSUMED | 60x, 60 minutes, D-15 day, LLM only for followed users | docs | |
| D-23 | Genie available in Free Edition for ask_data | PENDING (stretch) | | | |
| D-24 | Forecast horizon | DECIDED | 2 hours | team review | |
| D-25 | Puppet | DECIDED | 2D SwiftUI puppet first, 3D RealityKit upgrade behind the same interface | team review | |
| D-26 | Fold models for replay | DECIDED | 5 participant-grouped fold models plus a participant-to-fold map. Replay participants are predicted only by the fold that never saw them. Full model for teammates and the sandbox. Replay accuracy labeled out-of-sample. | all three leads | 2026-10-03 |
| D-27 | Acting-as | DECIDED | Following p_xxx means acting as p_xxx. Their meals are withheld and come due as meal_due cards, auto-logged as replay_auto after 10 replay minutes. Non-matching chat meals become simulations. | all three leads | 2026-10-03 |
| D-28 | Walk honesty | DECIDED | Phone walks overlay the followed participant. Windows overlapping a phone walk on replayed data get walk_effect_graded false and are excluded from accuracy. | all three leads | 2026-10-03 |
| D-29 | Notifications | DECIDED | In-app banners in the foreground. Local notifications scheduled ahead from StreamStatus.replay_anchor in the background. | all three leads | 2026-10-03 |
| D-30 | Dexcom sandbox mode | DECIDED | Status-only by default. Optional "Sandbox (time-shifted)" mode. | all three leads | 2026-10-03 |
| D-31 | Fleet location | DECIDED | Projector web view only. The phone gets a Follow picker sheet. 15 or 16 tiles per D-20. | all three leads | 2026-10-03 |
| D-32 | Comparison field names | ASSUMED | last_value_* replaces baseline_* in Prediction, Grade, State.today, FleetEntry, and /fleet. Owners (Data, Backend) confirm. Data confirmed 2026-10-03: gummi_model v1.1 grade() and the gummi_stream tables use last_value_* and cgm_only_*; Backend still to confirm | iOS Lead (default) | 2026-10-03 |
| D-33 | CGM-only baseline definition | DECIDED | One linear regression per horizon on the last 24 readings (the published method, 13.90 RMSE at 30 min reproduced), extended to every horizon, fold-matched. Data owner confirmed and shipped as model.cgm_only_forecast | Data owner (Nikhil) | 2026-10-03 |
| D-34 | Fleet accuracy cache and model loading | ASSUMED | A background task refreshes stream_gold_accuracy every 15 to 30 seconds, and /fleet serves the cache. gummi_model code ships in the App bundle, coefficients load from /Volumes/<CATALOG>/gummi_ml/artifacts/gummi_model_v1/. Owner (Backend) confirms. | iOS Lead (default) | 2026-10-03 |
| D-35 | Meal.source values and due_id | ASSUMED | "chat", "manual", "replay", "replay_due", "replay_auto". The log_due_meal action carries due_id. Owner (Backend) confirms. | iOS Lead (default) | 2026-10-03 |
| D-36 | Background meal_due notifications | PENDING | The phone schedules only clock-based notifications (06:00 briefing, 20:00 recap) until Backend decides whether State gets an upcoming meal_due list (a CONTRACT CHANGE REQUEST). | | |
| D-37 | Excluded participants in replay | DECIDED | Participants excluded under D-20 (015) are not replayed; replay_cgm and replay_meals hold 15 participants. Data owner confirmed | Data owner (Nikhil) | 2026-10-03 |
| D-38 | BIG IDEAs download route | DECIDED | B: filtered download on the laptop (data/scripts/download_bigideas.py: Dexcom, Food_Log, HR, Demographics, LICENSE, SHA256SUMS; 51 files, 240 MB, checksums verified), uploaded with the CLI to /Volumes/workspace/gummi_data/raw_bigideas/bigideas_1.1.3 | Nikhil | 2026-10-03 |
| D-39 | HR files for the ablation | ASSUMED | Treated the route-B download (HR included) as approval of the HR ablation. Result: no gain, HR stays out of the model | Data agent | 2026-10-03 |
| D-40 | Food-log cleaning | ASSUMED | (1) Standardized breakfast: logged_food or searched_food matches standard/std plus breakfast/bfast/bkfst, or contains "frosted flake". Finds 3 to 5 per participant, all 16, exposed as is_standard_breakfast. (2) Two rows (012 almonds, 010 bacon) log fat grams equal to their calories, so silver_meals re-derives fat as (calories - 4 carbs - 4 protein) / 9. 30-minute RMSE moves from 13.27 to 13.26, and meal-time peak error from 22.9 to 22.7. data/bigideas/silver.py | Data agent | 2026-10-03 |
| D-41 | gummi_model settings | ASSUMED | Ridge per horizon (alpha 10) on the change from the last reading; 48 horizons of 5 min; 10/90 residual bands split meal vs quiet windows; gamma absorption kernels peaking at carbs 55, sugar 35, fiber 90, protein 120, fat 150 min. Chosen on participant-grouped CV; reversible | Data agent | 2026-10-03 |
| D-42 | Morning-carbs feature | ASSUMED | Off: better breakfast peaks but no overall gain and slightly worse meal-window RMSE | Data agent | 2026-10-03 |
| D-43 | Walk effect cap | DECIDED (with D-11) | A walk lowers the forecast by at most 50% of the meal's predicted effect, so a 20 mg/dL literature effect never erases a small snack | Nikhil | 2026-10-03 |
| D-44 | Cadence below 100 steps/min | ASSUMED | 1 to 99 steps/min is "light" (the paper defines moderate from 100); 0 is "sedentary" | Data agent | 2026-10-03 |
| D-45 | Replay clock for model inputs | ASSUMED (Backend accepted) | A participant's local clock time maps to the same clock time on the replay date in the profile timezone, stored as UTC; the replayed user's profile carries that timezone so time-of-day features stay local. data/scripts/make_test_events.py | Data agent | 2026-10-03 |
| D-46 | Bundle without development mode | ASSUMED | data/databricks.yml target dev has no "mode: development": clean names for judges (gummi_stream, gummi_data_load_train) and continuous mode is honored. One Data Lead deploys | Data agent | 2026-10-03 |
| D-47 | IMU50 check details | ASSUMED | Subjects 00, 05, 13, 20, 44, first 24 hours each, read from the Zenodo zip with HTTP range requests (about 170 MB per subject); cadence per minute from the wrist accelerometer's dominant periodicity (a heuristic, not a step counter), compared with the ActiGraph's hourly METs | Data agent | 2026-10-03 |
| D-48 | Personal layer fit | ASSUMED | update_personal fits the carb factor and a constant offset together on the person's closed meal windows (shrunk toward 1 and 0), instead of averaging grade errors that already include the previous offset | Data agent | 2026-10-03 |
| D-49 | Fold models implementation (D-26) | ASSUMED | The 5 folds are the baseline-reproduction folds. Each fold component holds Gummi and CGM-only coefficients; its bands come from out-of-fold residuals of the other folds. for_user returns the full model for any id not in the fold map (u_*, sandbox). One gummi_model_v1/ (model.npz plus meta.json) holds everything | Data agent | 2026-10-03 |

## Status board

| Role | Phase | Last update | Blocked on |
|---|---|---|---|
| iOS Lead | 0 | | |
| Backend Lead | 0 | | |
| Data Lead | 3 (Phases 0 to 2 done; v1.1 model shipped; IMU50 check running) | 2026-10-03 | Nikhil: approve judge-facing numbers |
