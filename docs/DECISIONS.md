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
| iOS Lead | COMPLETE | 2026-10-03 |
| Backend Lead | INCOMPLETE | |
| Data Lead | INCOMPLETE | |

## Decisions

| ID | Decision | Status | Answer | By | When |
|---|---|---|---|---|---|
| D-01 | Names per role | DECIDED | iOS Lead: Mahil (`mahilmanoharan`). Backend Lead: Pranav (`THEpranavsomalraju`). Data Lead: Nikhil (`NikhilAmbavaram`). | all three leads | 2026-10-03 |
| D-02 | Workspace URL and owner | PENDING | | | |
| D-03 | Live store | DECIDED | In-memory hot state in the App plus Delta tables through the landing volume and pipeline. No Lakebase. | team review | |
| D-04 | LLM serving endpoint (tool calling required) | PENDING | | | |
| D-05 | Model hosting | DECIDED | gummi_model runs inside the App process on CPU | team review | |
| D-06 | iPhone token type and delivery | PENDING (auth spike) | | | |
| D-07 | Unity Catalog catalog | PENDING | | | |
| D-08 | Nutrition source | DECIDED | LLM estimate plus 30 seed foods, editable portions. No USDA. | team review | |
| D-09 | Modeling libraries on serverless | PENDING | | | |
| D-10 | iPhone iOS version, Xcode version, minimum target | DECIDED | iPhone 17 Pro (iPhone18,1), iOS 26.6.2 (23G90), Developer Mode on. Mac: macOS 26.6.2, Xcode 26.4 (17E192), XcodeGen 2.46.0. Minimum target iOS 18.0 (RealityView). Verified with sw_vers, xcodebuild, devicectl. If Xcode 26.4 can't deploy to iOS 26.6.2, Mahil updates Xcode. | iOS Lead | 2026-10-03 |
| D-11 | Walk effect source | PENDING | Default "literature" with citation until a personal permutation test passes | | |
| D-12 | High and low lines | ASSUMED | 140 and 70 mg/dL | docs | |
| D-13 | Bundle ID and Personal Team ID | DECIDED | Bundle ID com.mahilmanoharan.gummi. Free Personal Team "Mahil Manoharan (Personal Team)", Team ID 656VZ34X6H (verified in Xcode defaults: isFreeProvisioningTeam = 1). Free only: 7-day installs, no server push. | iOS Lead | 2026-10-03 |
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
| D-25 | Puppet | DECIDED | 3D RealityKit puppet from the start, behind the PuppetRenderer protocol so a simpler fallback stays possible. Replaces "2D first, 3D upgrade". No 2D timebox: push on 3D. Any fallback toggle is debug-only and hidden in filming mode. Look (Mahil): an original koala, smooth eucalyptus-green gummy-jelly material with soft rounded features (big round ears, oval nose, small dot eyes, seated pose), never fuzzy. Mood colors in CONTRACT section 9 stay. Recoloring the body per mood is tabled. Build a base first, then iterate on the phone. | iOS Lead | 2026-10-03 |
| D-26 | Fold models for replay | DECIDED | 5 participant-grouped fold models plus a participant-to-fold map. Replay participants are predicted only by the fold that never saw them. Full model for teammates and the sandbox. Replay accuracy labeled out-of-sample. | all three leads | 2026-10-03 |
| D-27 | Acting-as | DECIDED | Following p_xxx means acting as p_xxx. Their meals are withheld and come due as meal_due cards, auto-logged as replay_auto after 10 replay minutes. Non-matching chat meals become simulations. | all three leads | 2026-10-03 |
| D-28 | Walk honesty | DECIDED | Phone walks overlay the followed participant. Windows overlapping a phone walk on replayed data get walk_effect_graded false and are excluded from accuracy. | all three leads | 2026-10-03 |
| D-29 | Notifications | DECIDED | In-app banners in the foreground. Local notifications scheduled ahead from StreamStatus.replay_anchor in the background. | all three leads | 2026-10-03 |
| D-30 | Dexcom sandbox mode | DECIDED | Status-only by default. Optional "Sandbox (time-shifted)" mode. | all three leads | 2026-10-03 |
| D-31 | Fleet location | DECIDED | Projector web view only. The phone gets a Follow picker sheet. 15 or 16 tiles per D-20. | all three leads | 2026-10-03 |
| D-32 | Comparison field names | DECIDED | last_value_* replaces baseline_* in Prediction, Grade, State.today, FleetEntry, and /fleet. Confirmed by Backend and Data. Backend maps any baseline_* to last_value_* at the API boundary. | iOS Lead, confirmed by owners | 2026-10-03 |
| D-33 | CGM-only baseline definition | DECIDED | One linear model per horizon on CGM history only (the published method extended to every horizon), fold-matched. Confirmed by Data (last 24 readings, reproduced 13.90 RMSE at 30 min). cgm_only_mae_mg_dl can be null. | iOS Lead, confirmed by Data | 2026-10-03 |
| D-34 | Fleet accuracy cache and model loading | DECIDED | A background task refreshes stream_gold_accuracy every 15 to 30 seconds, and /fleet serves the cache. gummi_model code ships in the App bundle, coefficients load from /Volumes/<CATALOG>/gummi_ml/artifacts/gummi_model_v1/. Confirmed by Backend (refresh every 20 s). | iOS Lead, confirmed by Backend | 2026-10-03 |
| D-35 | Meal.source values and due_id | DECIDED | "chat", "manual", "replay", "replay_due", "replay_auto". The log_due_meal action carries due_id, format "d_<n>". Confirmed by Backend. | iOS Lead, confirmed by Backend | 2026-10-03 |
| D-36 | Background meal_due notifications | DECIDED | CONTRACT 1.2 (backend/work, merges at phase end): State.upcoming_due lists the next 6 replay hours of due meals with due_at already in wall-clock time. The phone schedules local notifications from it plus the 06:00 briefing and 20:00 recap. | Backend Lead, human-approved | 2026-10-03 |
| D-37 | Excluded participants in replay | DECIDED | Participants excluded under D-20 are not replayed. Confirmed by Data: p_015 excluded, 15 replayed. | iOS Lead, confirmed by Data | 2026-10-03 |
| D-38 | App palette | PENDING | Eucalyptus green for accents and highlights (Mahil). Main color still to pick. Until then the app uses a neutral placeholder token that is easy to swap. | iOS Lead | 2026-10-03 |

## Status board

| Role | Phase | Last update | Blocked on |
|---|---|---|---|
| iOS Lead | 0 | 2026-10-03: onboarding items 1 to 3 and 5 verified, D-10 recorded, D-25 changed to 3D, onboarding COMPLETE, D-32 to D-37 confirmed | Phone credentials from Backend (not blocking, MockAPI) |
| Backend Lead | 0 | | |
| Data Lead | 0 | | |
