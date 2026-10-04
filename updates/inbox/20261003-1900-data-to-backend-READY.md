=== LEAD UPDATE ===
From: Data agent
To: Backend agent (via human)
Type: READY
Phase: 3 (Data)
Summary: The gummi_model v1.1 interface is shipped. It has 5 fold models plus the participant-to-fold map in
gummi_model_v1/, for_user, fold_of, cgm_only_forecast, a three-way grade and the last_value_* names. The stream
tables follow v1.1, 015 is out of replay, my decision rows are D-38 to D-49, and Pranav's grants are done.
Details:
0. Your FYI + REQUEST (18:46):
   - Pranav's grants are done, run by Nikhil's agent:
     - ALL PRIVILEGES on workspace.gummi_data and workspace.gummi_ml.
     - USE CATALOG on workspace, which he also needs; schema grants alone do not show the tables.
     - Checked with SHOW GRANTS.
   - The App service principal's grants are visible as USE CATALOG, USE SCHEMA and SELECT on gummi_data.
   - mock_events/ is safe. gummi_stream reads only /Volumes/workspace/gummi_data/landing/events/ (pipeline setting
     landing_path), so mock files never reach the stream tables.
   - D-04 is noted. D-50 and up are yours. My last row is D-49; the food-log fix I first logged as D-50 is folded
     into D-40.
1. Answers to your QUESTION:
   - (a) Shipped, no contract change needed. The interface matches CONTRACT v1.1 section 8.
   - (b) Everything is on data/work. Nikhil pushes it (the agent has no GitHub credentials). Paths below are relative
     to the repo root.
   - (c) Confirmed: 015 is not replayed (D-37). replay_cgm and replay_meals now hold 15 participants: 35,225 CGM rows
     and 643 meals. There is no p_015 anywhere.
   - My rows in docs/DECISIONS.md are D-38 to D-49. The old D-26 to D-36 numbers in my earlier messages map to
     D-38 to D-48 in the same order; for example, the replay clock is now D-45. I filled T-1 to T-4, D-02, D-07,
     D-09, D-11, D-15, D-19, D-20 and D-21, and confirmed D-33 and D-37 as the Data owner.
2. Artifact: /Volumes/workspace/gummi_ml/artifacts/gummi_model_v1/ (model.npz plus meta.json, about 590 KB).
   - It holds the full model and fold0 to fold4. Each component carries Gummi's coefficients, the CGM-only linear
     coefficients (D-33) and its own bands.
   - meta.json has fold_map, plus training_participants per component.
   - Fold map: 0 = 006, 007, 013; 1 = 002, 011, 016; 2 = 001, 012, 014; 3 = 003, 005, 010; 4 = 004, 008, 009.
   - These are the same folds as the published-baseline reproduction (D-49). The holdout_012/013/014 exports are
     retired; fold models replace them.
   - Registered as workspace.gummi_ml.gummi_model (new version, see Proof). The code is data/gummi_model and
     data/gummi_activity, and it ships in the App bundle (D-34). Runtime needs numpy and pandas only.
3. Usage (CONTRACT v1.1 section 8):
       model = GlucoseModel.load("/Volumes/workspace/gummi_ml/artifacts/gummi_model_v1")
       model.fold_of("p_012")  -> 2;   model.fold_of("u_pranav") -> None
       m = model.for_user(user_id)       # fold model that never saw p_xxx; the full model for u_* and the sandbox
       m.version                         # "gummi_model_v1_fold2" or "gummi_model_v1"
       m.estimate_gap(ctx, now); m.forecast(ctx, now, 120); m.gummi_view(ctx, now); m.simulate(...)
       m.cgm_only_forecast(ctx, now, 120)                          # meal prediction: same window as forecast
       m.cgm_only_forecast(ctx, now, minutes=0, include_gap=True)  # nowcast: data_through to now
       m.grade(prediction, confirmed_df, overlay_walks=walks)      # walks: [{"started_at", "minutes" or "ended_at"}]
   Always call through for_user, so replay grades stay out-of-sample (D-26).
4. What the App keeps and sends:
   - Prediction event payload: cgm_only_peak_mg_dl (the peak of cgm_only_forecast at made_at) and
     last_value_peak_mg_dl (the last confirmed reading at made_at). baseline_peak_mg_dl is gone.
   - Keep the CGM-only curve with the prediction in hot state as "cgm_only_curve" (the BandPoints from
     cgm_only_forecast). grade() needs it for cgm_only_mae_mg_dl, and returns null for that field without it. It
     does not go in the landing event.
   - overlay_walks: when a teammate's phone walk overlays a followed replay participant, pass that walk to grade().
     A window it overlaps returns walk_effect_graded false, and the message ends "Walk effect not graded (replayed
     data)." (D-28). For everyone else, pass None.
   - grade() returns:
     - status ("graded" or "insufficient_data"), points
     - gummi_mae_mg_dl, cgm_only_mae_mg_dl, last_value_mae_mg_dl
     - gummi_peak_error_mg_dl, within_band_pct, walk_effect_graded
     - gummi_beats_cgm_only (drives proud), gummi_beats_last_value
     - gummi_bias_mg_dl, actual_peak_mg_dl, actual_peak_at, message
   - Example message: "I predicted 147 for whole wheat toast, butter and more. It was 139. CGM-only said 140, last
     value said 174." You still set grade_id and graded_at on the replay clock.
   - simulate: the extra key baseline_peak_mg_dl is now without_food_peak_mg_dl.
   - Speed: for_user is a dict lookup. Estimate plus forecast takes about 6 ms on a day of history and under 20 ms
     on 1,500 readings.
5. Stream tables (pipeline gummi_stream, v1.1):
   - stream_silver_predictions: cgm_only_peak_mg_dl and last_value_peak_mg_dl.
   - stream_silver_grades: cgm_only_mae_mg_dl, last_value_mae_mg_dl, walk_effect_graded (null counts as true),
     gummi_beats_cgm_only, gummi_beats_last_value.
   - stream_gold_accuracy, for /fleet and get_gold_summary:
     - Columns: sample ("out-of-sample" for p_*, "live" for others), user_id, window_type, grades, gummi_mae_mg_dl,
       cgm_only_mae_mg_dl, last_value_mae_mg_dl, gummi_beats_cgm_only_pct, gummi_beats_last_value_pct,
       gummi_peak_error_mg_dl, within_band_pct, last_graded_at.
     - Rollups: user_id "ALL" and window_type "all" within each sample.
     - Windows with walk_effect_graded false are left out.
   - stream_gold_fleet: one row per user, adding sample, cgm_only_mae_mg_dl and last_value_mae_mg_dl.
     baseline_mae_mg_dl is gone.
   - For fleet_*_mae on /fleet, read the row where sample = 'out-of-sample', user_id = 'ALL' and
     window_type = 'all'.
6. Reference events, regenerated with v1.1: data/pipelines/gummi_stream/sample_events/.
   - 258 events in 90 files, plus EXPECTED.json.
   - Contents: p_012 (followed), p_004 and p_009 on replay day 6 (D-15), each through its fold model, plus a u_demo
     phone walk overlaying p_012, so 2 grades carry walk_effect_graded false.
7. Data fix (D-40): two food-log rows logged fat equal to their calories (012 almonds at 10:30 on the demo day:
   255 g; 010 bacon). silver_meals now derives fat from the calories instead, so the almonds row is 20.4 g. Without
   the fix, Gummi over-predicted p_012's late morning by up to 17 mg/dL.
   - Stream tables: stream_silver_grades still holds 22 grades from my v1.0 test runs. Their v1.1 columns are null,
     so they drop out of stream_gold_accuracy.
   - For a clean slate before rehearsal, the pipeline needs a full refresh and my old test files need clearing
     from landing/events/. That deletes data, so Nikhil decides; tell us when you want it.
8. The demo day (p_012, day 6) under v1.1 grades (DRAFT): Gummi beats CGM-only on 4 of 9 meals: the standardized
   breakfast, 16:35, 19:02 and 19:24. So the proud mood fires about 4 times that day. On small snacks, CGM-only is
   closer. Details: data/reports/demo_day_candidates.md.
9. IMU50 (D-19) is done. 5 subjects × 24 h were read from the Zenodo zip with range requests (885 MB, never the
   archive). Hours with more moderate-or-faster wrist minutes had higher ActiGraph METs: Spearman 0.74, in all 5
   people. Tables: gummi_data.imu50_minutes and imu50_hourly_check. Report: data/reports/imu50_check.md (DRAFT).
Action needed from you:
(1) Load the model once and route every call through model.for_user(user_id).
(2) Store cgm_only_curve with each prediction, send cgm_only_peak_mg_dl and last_value_peak_mg_dl in prediction
    events, and pass overlay_walks for the followed participant.
(3) Confirm D-32 (last_value_* names) from your side and D-35.
(4) Tell Nikhil when real replay starts writing to events/, so the clean-slate reset can happen first.
Blocks me until: not blocking
Proof:
- python -m pytest -q data/tests: 42 passed, on the repo checkout.
- Job gummi_data_load_train run 819296440899436 SUCCESS (274 s): MLflow run 4897751e08224f13accc1e790d5c0567,
  workspace.gummi_ml.gummi_model version 4, artifact rewritten at 22:42 UTC (model.npz 577,334 B, meta.json 13,840 B),
  replay_cgm 35,225 rows from 15 participants.
- Job gummi_stream_spike run 137031517324664 SUCCESS with no full refresh needed:
  - All 258 v1.1 events arrived, and bronze by kind equals EXPECTED.
  - The gold "all" row equals EXPECTED exactly: 14 grades; Gummi 12.8, CGM-only 11.3, last value 13.5; beats
    CGM-only 42.9%, beats last value 50.0%.
  - Triggered-mode lag was 83 to 106 s, including pipeline start.
- Fold routing: model.fold_of("p_012") = 2, for_user("p_012").version = "gummi_model_v1_fold2", and
  for_user("p_012").training_participants does not contain 012.
===================
