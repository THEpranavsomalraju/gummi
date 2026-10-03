# Decisions Log

Agents append rows. Status values: DECIDED (a human chose), ASSUMED (an agent chose a reversible default, humans review), PENDING (needs a human).

## Team answers needed (humans fill these in)

| ID | Question | Answer |
|---|---|---|
| T-1 | Progress: workspace created? LinkedIn verification done? Dexcom developer app created? Xcode project on the phone? BIG IDEAs downloaded? | PENDING |
| T-2 | Did organizers require using both datasets (BIG IDEAs and IMU50)? Decides whether IMU50 stays. | PENDING |
| T-3 | Output of `databricks serving-endpoints list --profile gummi` | PENDING (Backend agent collects) |
| T-4 | Real header row and first 3 lines of one Dexcom file and one food log | PENDING (Data agent collects) |
| T-5 | Who holds which role, plus comfort with Swift, Spark, FastAPI | iOS Lead: Mahil (`mahilmanoharan`). Backend Lead: Pranav (`THEpranavsomalraju`). Data Lead: Nikhil (`NikhilAmbavaram`). Comfort levels: each lead adds at onboarding. |
| T-6 | Agree with the reframe: non-insulin users, coaching first, nowcast as the engine? | Yes, agreed by all three leads |

## Onboarding status

| Role | Onboarding interview | Done at |
|---|---|---|
| iOS Lead | INCOMPLETE | |
| Backend Lead | PARTIAL: name, repo, Python 3.12 venv, CLI profile gummi (somalrajupc@gmail.com, admin), workspace, LinkedIn, catalog, D-04 done. MLflow experiment /Users/somalrajupc@gmail.com/gummi-agent (id 3505481683626519). Open: Dexcom account, secrets | 2026-10-03 |
| Data Lead | INCOMPLETE | |

## Decisions

| ID | Decision | Status | Answer | By | When |
|---|---|---|---|---|---|
| D-01 | Names per role | DECIDED | iOS Lead: Mahil (`mahilmanoharan`). Backend Lead: Pranav (`THEpranavsomalraju`). Data Lead: Nikhil (`NikhilAmbavaram`). | all three leads | 2026-10-03 |
| D-02 | Workspace URL and owner | DECIDED | https://dbc-0f92eb43-532a.cloud.databricks.com (workspace ID 7474657192035402), owner Nikhil, LinkedIn verification done. <APP_URL> = https://gummi-7474657192035402.aws.databricksapps.com (App "gummi", source /Workspace/Users/somalrajupc@gmail.com/gummi-backend) | Nikhil / Backend agent verified | 2026-10-03 |
| D-03 | Live store | DECIDED | In-memory hot state in the App plus Delta tables through the landing volume and pipeline. No Lakebase. | team review | |
| D-04 | LLM serving endpoint (tool calling required) | DECIDED (Pranav: "whatever is optimal") | databricks-gpt-oss-120b, fallback databricks-qwen3-next-80b-a3b-instruct. All 7 chat endpoints returned a correct log_meal tool call (backend/scripts/llm_tool_test.py); gpt-oss-120b 1.4 s with clean arguments, streaming first token 0.6 to 1.5 s. No Claude endpoint in the workspace. | Backend agent | 2026-10-03 |
| D-05 | Model hosting | DECIDED | gummi_model runs inside the App process on CPU | team review | |
| D-06 | iPhone token type and delivery | DECIDED (verified end to end) | Service principal gummi-iphone (application id 2cc103a1-493a-4c74-a43f-955f5625b41d, CAN USE on App gummi). The phone POSTs client_credentials with scope=all-apis to https://dbc-0f92eb43-532a.cloud.databricks.com/oidc/v1/token (Basic auth with client id and secret), gets a 3600 s bearer token, refreshes 5 minutes before expiry and on any 401. Secret valid until 2028-10-02, kept in backend/secrets/iphone_sp.env and the iOS Secrets.xcconfig.local only. Note: the secret must be generated with the all-apis scope; a sql-scoped secret gets 401 from the App. Verified: /health 200, /live pings unbuffered, every Phase 1 route 25 to 70 ms through the proxy (backend/scripts/smoke.py). | Pranav (Backend Lead) | 2026-10-03 |
| D-07 | Unity Catalog catalog | DECIDED | workspace (the only writable catalog). Schemas workspace.gummi_data and workspace.gummi_ml | Data Lead | 2026-10-03 |
| D-08 | Nutrition source | DECIDED | LLM estimate plus 30 seed foods, editable portions. No USDA. | team review | |
| D-09 | Modeling libraries on serverless | PENDING | | | |
| D-10 | iPhone iOS version, Xcode version, minimum target | PENDING | | | |
| D-11 | Walk effect source | PENDING | Default "literature" with citation until a personal permutation test passes | | |
| D-12 | High and low lines | ASSUMED | 140 and 70 mg/dL | docs | |
| D-13 | Bundle ID and Personal Team ID | PENDING | | | |
| D-14 | Final name | DECIDED | Gummi (project and puppet) | all three leads | 2026-10-03 |
| D-15 | Followed participant and replay day for the demo | PENDING (Data proposes 3) | | | |
| D-16 | Repo URL | DECIDED | https://github.com/mahilmanoharan/gummi (public). Branches main, ios/work, backend/work, data/work. | iOS Lead | 2026-10-03 |
| D-17 | Dexcom OAuth path | ASSUMED | Connect from the App's web page in a laptop browser, callback at <APP_URL>/api/v1/dexcom/callback. Verify in the auth spike. | docs | |
| D-18 | Dexcom sandbox user, data range, live or repeating | PENDING (expect repeating, fixed range) | | | |
| D-19 | IMU50 scope | PENDING (depends on T-2). If required: small validation of cadence bands only. | | | |
| D-20 | BIG IDEAs participant exclusions | PENDING | | | |
| D-21 | Pipeline mode: continuous, or triggered every minute | PENDING (streaming spike) | | | |
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
| D-32 | Comparison field names | ASSUMED (Backend confirmed; Data to confirm) | last_value_* replaces baseline_* in Prediction, Grade, State.today, FleetEntry, and /fleet. Owners (Data, Backend) confirm. | iOS Lead (default) | 2026-10-03 |
| D-33 | CGM-only baseline definition | ASSUMED | One linear model per horizon on CGM history only (the published method extended to every horizon), fold-matched. Owner (Data) confirms. | iOS Lead (default) | 2026-10-03 |
| D-34 | Fleet accuracy cache and model loading | DECIDED (Backend confirmed, 20 s refresh) | A background task refreshes stream_gold_accuracy every 15 to 30 seconds, and /fleet serves the cache. gummi_model code ships in the App bundle, coefficients load from /Volumes/<CATALOG>/gummi_ml/artifacts/gummi_model_v1/. Owner (Backend) confirms. | iOS Lead (default) | 2026-10-03 |
| D-35 | Meal.source values and due_id | DECIDED (Backend confirmed, due_id "d_<n>") | "chat", "manual", "replay", "replay_due", "replay_auto". The log_due_meal action carries due_id. Owner (Backend) confirms. | iOS Lead (default) | 2026-10-03 |
| D-36 | Background meal_due notifications | DECIDED | Yes. State.upcoming_due lists the next 6 replay hours of due meals with wall-clock due_at, so the phone schedules meal_due notifications in the background (CONTRACT 1.2). | Pranav (Backend Lead) | 2026-10-03 |
| D-37 | Excluded participants in replay | DECIDED (Data confirmed: 015 not replayed) | Participants excluded under D-20 are not replayed. Owner (Data) confirms. | iOS Lead (default) | 2026-10-03 |
| D-50 | Mock events location | ASSUMED | Mock mode writes StreamEvents to /Volumes/workspace/gummi_data/landing/mock_events/, a sibling of events/, so synthetic data never reaches the gummi_stream tables. Live mode writes to events/. Verified: the deployed App wrote 2 files (30 events) with its own service principal. Backend rows use D-50 and up, Data renumbers from D-38. | Backend agent | 2026-10-03 |

## Status board

| Role | Phase | Last update | Blocked on |
|---|---|---|---|
| iOS Lead | 0 | | |
| Backend Lead | 1: every route deployed in mock mode, 14 contract tests pass, smoke test passes through the proxy with the phone token, App writes to landing | 2026-10-03 | Nikhil: Pranav's own UC grants on gummi_data and gummi_ml; v1.1 model |
| Data Lead | 0 | | |
