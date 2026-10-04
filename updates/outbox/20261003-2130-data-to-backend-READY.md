=== LEAD UPDATE ===
From: Data agent
To: Backend agent (via human)
Type: READY
Phase: 3 (Data)
Summary: Ask B is done. The big-meal term lowers MAE at 30 to 120 min in every window, leaves 180 min identical,
and moves peak bias from -14.4 to -10.7 mg/dL. All five pieces of ask C are built and granted. One catch: the new
artifact needs the updated gummi_model code, so it waits at gummi_model_v1_next/ until the App ships that code.
Details:
A. Ask B: big-spike under-prediction (D-70, all numbers DRAFT until Pranav approves)
1. What changed:
   - One meal feature, carbs_big_g: carbs above 40 g on the carb kernel. Option (b), a nonlinear carb term,
     as a hinge.
   - It is ramped out between 150 and 180 min after data_through, so the 180-min point is exactly the v1.1 model.
     The blend is folded into one linear model per horizon, so the curve has no step.
   - Tried and rejected: carbs plus sugar hinges, fast and slow carb kernels, hinge at 30 or 60 g, other kernel
     peaks. Option (a) adds nothing a hinge does not. Option (c) was not tried, because it gives up MAE to raise
     peaks.
   - Full table: data/reports/spike_fix.md.
2. Before and after, participant-grouped CV on the same 5 folds (MAE in mg/dL):
   - Folds: better in 5 of 5 at 30, 60 and 90 min; 4 of 5 at 120; equal at 180.

   | Window | 30 min | 60 min | 90 min | 120 min | 180 min |
   |---|---|---|---|---|---|
   | all | 9.04 → 8.90 | 12.35 → 12.06 | 13.46 → 13.15 | 14.37 → 14.24 | 15.15 → 15.15 |
   | meal | 11.71 → 11.48 | 16.20 → 15.72 | 17.28 → 16.82 | 18.08 → 17.89 | 18.48 → 18.48 |
   | quiet | 6.39 → 6.35 | 8.56 → 8.47 | 9.71 → 9.56 | 10.75 → 10.68 | 11.95 → 11.95 |

   - Baselines are unchanged, for example 60 min all windows: CGM-only 13.42, last value 14.87.
   - Band coverage is unchanged: 0.80 overall; 0.80 to 0.74 in meal windows.
   - Fold spread, RMSE SD at 60 min all windows: 2.06.
3. At meal time, 602 held-out meals:

   | Measure | Before | After |
   |---|---|---|
   | Peak bias | -14.4 | -10.7 |
   | Peak error | 22.7 | 20.4 |
   | Curve error | 18.3 | 18.0 |
   | Standardized breakfast peak bias | -40.3 | -31.4 |
   | Standardized breakfast peak error | 42.5 | 35.1 |

   - Meals whose real peak reached 140: the forecast reaches 140 for 135 of 292, against 93 before.
   - False 140s go from 27 to 41 meals. Precision stays at 77%.
   - Curve beats last value on 65.4% of meals, against 66.8% before.
4. Demo day (p_012, day 6, fold 2):
   - Breakfast: "I predicted 153. It was 174." It was 143 before, so the breakfast forecast now crosses 140.
   - 19:24 candy: "I predicted 164. It was 161."
   - Gummi still beats CGM-only on 4 of 9 meals that day.
5. Personal layer (D-71): it shrinks harder toward the population model now (pseudo-counts 8 and 9). It is a small
   net gain: peak error 20.4 → 19.9, curve error +0.05. update_personal has the same interface.
6. Deployment, the one catch:
   - The new artifact lists carbs_big_g in meta.meal_cols, and only the new gummi_model code derives it. Old code
     plus the new artifact raises a KeyError.
   - So /Volumes/workspace/gummi_ml/artifacts/gummi_model_v1/ is back to v1.1 (model version 4), and your running
     App is safe on restart.
   - The new model is at /Volumes/workspace/gummi_ml/artifacts/gummi_model_v1_next/ and is registered as
     workspace.gummi_ml.gummi_model version 5.
   - The new code also loads the v1.1 artifact. Steps:
     (1) Copy data/gummi_model from data/work into the App bundle.
     (2) Deploy.
     (3) Load gummi_model_v1_next, or tell me and I copy it over gummi_model_v1.
   - Latency on 012's full history (2,169 readings, 76 meals): estimate plus forecast 28 ms, simulate 63 ms.
   - Until then I will not rerun the training job, because it rewrites gummi_model_v1.
B. Ask C: sub-agents for Gummi Insights (D-72; all in workspace, catalog workspace)
   a) workspace.gummi_data.get_gold_summary(user_id STRING, days INT DEFAULT 1) RETURNS TABLE
      - Columns: sample, user_id, window_type, grades, gummi_mae_mg_dl, cgm_only_mae_mg_dl, last_value_mae_mg_dl,
        gummi_beats_cgm_only_pct, gummi_beats_last_value_pct, gummi_peak_error_mg_dl, within_band_pct,
        last_graded_at.
      - Rows: every rollup for that user, plus the out-of-sample ALL rollup by window type.
      - It uses the same rules as stream_gold_accuracy (walk-overlapped windows left out). days counts calendar
        days on the replay clock with today as 1; 0 or NULL means all time.
      - Example: SELECT * FROM workspace.gummi_data.get_gold_summary('p_012', 1)
      - Source: data/sql/get_gold_summary.sql
   b) workspace.gummi_data.meal_response_stats(user_id STRING) RETURNS TABLE. 'ALL' gives everyone.
      - One row per meal: carbs_g, sugar_g, glucose_before_mg_dl, actual_peak_mg_dl, actual_rise_mg_dl,
        readings_in_window, predicted_peak_mg_dl, cgm_only_peak_mg_dl, last_value_peak_mg_dl, the three curve
        errors, gummi_peak_error_mg_dl, gummi_beats_cgm_only, walk_effect_graded.
      - Source: data/sql/meal_response_stats.sql
   c) Genie space "Gummi Data": space_id 01f1bf87ea5918298b59e25b38538d16 (warehouse 1b929fe5bf415d65).
      - Tables: stream_gold_accuracy, stream_gold_fleet, stream_silver_grades, stream_silver_predictions,
        stream_silver_meals, stream_silver_cgm, replay_meals.
      - Instructions as you asked: baselines always shown, out-of-sample label, mg/dL, no treatment advice, draft
        numbers.
      - 10 sample questions, 4 example SQLs, 8 benchmark questions.
      - Benchmark eval run 01f1bf8d011518ca963e2645f64e5e4f: 8 of 8 correct.
      - Definition: data/agent_bricks/genie_space_gummi_data.json
   d) AI/BI dashboard "Gummi live accuracy": dashboard_id 01f1bf883268170693784c519c8eb10b, path
      /Shared/gummi/Gummi live accuracy, published with embedded credentials.
      - Counters: Gummi, CGM-only and last-value error; grades; pipeline lag over the last 10 min; events in the
        last minute.
      - Charts: three-way error by window and by participant, error by replay hour, grades landing per minute,
        pipeline lag per minute, events per minute by kind.
      - I could not view it rendered (my browser is not signed in to the workspace). Please open it once and tell me
        if any widget shows an error.
      - Definition: data/agent_bricks/dashboard_gummi_live_accuracy.json
   e) Knowledge Assistant "Gummi Reports": id d8755a47-88a6-4c60-8942-99a903a99ad6, endpoint
      ka-d8755a47-endpoint.
      - Source: volume /Volumes/workspace/gummi_ml/knowledge/ holding model_eval.md, spike_fix.md,
        walk_effect.md (Buffey et al. 2022), imu50_check.md, phase1_findings.md and limits_and_sources.md (the
        limits paragraph). Every file is labeled DRAFT, and the instructions say to call numbers draft.
      - The source was still indexing when I sent this. Query the endpoint after its source shows UPDATED or ACTIVE.
   Grants on the App service principal aa7965f7-bb19-4209-a927-cafe95785e49:
   - EXECUTE on both functions
   - CAN_RUN on the Genie space
   - CAN_QUERY on the Knowledge Assistant
   - It already had SELECT on gummi_data.
   Pranav: CAN_MANAGE on the Knowledge Assistant. The admins group manages the Genie space and the dashboard.
C. Coordination
   1. The stream tables still hold my test fixtures, so Genie and the dashboard show fixture numbers until the
      clean slate. Tell me before real replay writes to landing/events/; I full-refresh gummi_stream and clear my
      old test files then (Nikhil OKs the deletion).
   2. Continuous mode for rehearsal, filming and judging: tell me the time window; I deploy with continuous=true
      and stop it afterward.
   3. Decision IDs: D-23 (Genie available: yes), D-70, D-71 and D-72 are mine, from the Data block that starts at
      D-70.
Action needed from you:
(1) Ship the updated data/gummi_model in the App, then load gummi_model_v1_next or ask me to swap it in.
(2) Attach get_gold_summary, meal_response_stats, the Genie space and the Knowledge Assistant to Gummi Insights,
    and link the dashboard.
(3) Open the dashboard once and report any widget error.
(4) Give me the clean-slate time and the continuous-mode window.
Blocks me until: not blocking
Proof:
- pytest data/tests: 45 passed, locally and on the repo checkout.
- Job gummi_data_load_train run 1057459221921688: SUCCESS, MLflow run 05a57d7172484853bed7ad0db35f9936, model
  version 5. Its eval_results match the local run (60 min all windows: MAE 12.06, RMSE 17.48, coverage 0.80).
- The CV runs are in data/local_out/spike_experiment/ and in data/scripts/spike_experiment.py and
  spike_select_cutoff.py.
- SHOW GRANTS shows EXECUTE for the service principal on both functions.
===================
