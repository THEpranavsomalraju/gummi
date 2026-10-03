# Draft for CONTRACT.md section 10 (Tables), version 1.2

DRAFT, Data Lead (section owner). Changing CONTRACT.md is a hard stop: on the human's yes this text replaces the
current section 10 and the contract becomes 1.2. Column names and types are what the code writes today (checked
against the Databricks tables). Times: TIMESTAMP columns from the raw files are the participant's local clock as
recorded (the dataset shifted dates for privacy); stream tables hold UTC.

## `<CATALOG>.gummi_data` (catalog `workspace`, D-07)

Volumes: `raw_bigideas` (`bigideas_1.1.3/<ID>/{Dexcom,Food_Log,HR}_<ID>.csv`, `Demographics.csv`, `LICENSE.txt`,
`SHA256SUMS.txt`), `landing` (`events/<YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl`), `raw_imu50` only if D-19 needs files.

Batch tables (job `gummi_data_load_train`):

| Table | Columns |
|---|---|
| bronze_cgm | participant_id, index, timestamp_yyyy_mm_ddthhmmss, event_type, event_subtype, patient_info, device_info, source_device_id, glucose_value_mg_per_dl, insulin_value_u, carb_value_grams, duration_hhmmss, glucose_rate_of_change_mg_per_dl_per_min, transmitter_time_long_integer, source_file (all STRING, one row per raw line) |
| bronze_food_log | participant_id, date, time, time_begin, time_end, logged_food, amount, unit, searched_food, calorie, total_carb, dietary_fiber, sugar, protein, total_fat, source_layout, source_file (all STRING; time holds time or time_of_day) |
| bronze_demographics | id BIGINT, gender STRING, hba1c DOUBLE, participant_id STRING |
| bronze_hr | participant_id STRING, minute TIMESTAMP, hr_mean DOUBLE, samples BIGINT (ablation only) |
| silver_cgm_5min | participant_id STRING, ts TIMESTAMP, glucose DOUBLE, glucose_flag STRING (null, low, high), gap_before_min DOUBLE, island INT, day_index INT, minute_of_day INT |
| silver_meals | participant_id STRING, meal_id STRING (<ID>-NNN), eaten_at TIMESTAMP, calories, carbs_g, fiber_g, sugar_g, protein_g, fat_g DOUBLE, items STRING (" \| " joined), n_items INT, is_standard_breakfast BOOLEAN, meal_slot STRING (breakfast, lunch, dinner, late) |
| replay_cgm | user_id STRING (p_<ID>), participant_id STRING, day_index INT (1 = first CGM day), minute_of_day INT, t_offset_min DOUBLE (minutes from the first local midnight), glucose_mg_dl DOUBLE, island INT, excluded_from_training BOOLEAN |
| replay_meals | user_id, participant_id, meal_id STRING, day_index INT, minute_of_day INT, t_offset_min DOUBLE, items STRING, carbs_g, sugar_g, fiber_g, protein_g, fat_g, calories DOUBLE, is_standard_breakfast BOOLEAN, excluded_from_training BOOLEAN |

Stream tables (pipeline `gummi_stream`, SQL in data/pipelines/gummi_stream/):

| Table | Columns |
|---|---|
| stream_bronze_events | event_id, source, user_id, kind STRING, t, released_at TIMESTAMP, payload VARIANT, source_file STRING, landed_at, ingested_at TIMESTAMP, event VARIANT |
| stream_silver_cgm | event_id, user_id, source STRING, t, released_at TIMESTAMP, glucose_mg_dl DOUBLE, landed_at, ingested_at TIMESTAMP |
| stream_silver_meals | event_id, user_id, source, meal_id STRING, eaten_at TIMESTAMP, meal_source STRING, carbs_g, sugar_g, fiber_g, protein_g, fat_g, calories DOUBLE, items VARIANT, prediction_id STRING, released_at, ingested_at TIMESTAMP |
| stream_silver_predictions | event_id, user_id, prediction_id, prediction_kind STRING, made_at TIMESTAMP, about, meal_id STRING, window_start, window_end TIMESTAMP, predicted_peak_mg_dl, baseline_peak_mg_dl DOUBLE, status STRING, predicted_curve VARIANT, released_at, ingested_at TIMESTAMP |
| stream_silver_grades | event_id, user_id, grade_id, prediction_id, grade_kind STRING, graded_at TIMESTAMP, points INT, gummi_mae_mg_dl, baseline_mae_mg_dl, gummi_peak_error_mg_dl, within_band_pct DOUBLE, message STRING, gummi_beats_baseline BOOLEAN, released_at, ingested_at TIMESTAMP |
| stream_silver_cards | event_id, user_id, card_id, card_type STRING, created_at TIMESTAMP, title, body, mood, generated_by, trace_id STRING, released_at, ingested_at TIMESTAMP |
| stream_gold_fleet | user_id STRING, data_through TIMESTAMP, last_glucose_mg_dl DOUBLE, readings BIGINT, grades BIGINT, gummi_mae_mg_dl, baseline_mae_mg_dl DOUBLE, last_grade_message STRING, last_graded_at TIMESTAMP, last_card_type, last_card_title STRING, last_card_at TIMESTAMP, pipeline_lag_seconds DOUBLE |
| stream_gold_accuracy | user_id STRING ('ALL' = every user), window_type STRING (meal, quiet, 'all'), grades BIGINT, gummi_mae_mg_dl, baseline_mae_mg_dl, gummi_beats_baseline_pct, gummi_peak_error_mg_dl, within_band_pct DOUBLE, last_graded_at TIMESTAMP |

## `<CATALOG>.gummi_ml`

Volume `artifacts` (`gummi_model_v1/model.npz`, `meta.json`). Registered model `<CATALOG>.gummi_ml.gummi_model`.

| Table | Columns |
|---|---|
| eval_results | model STRING (gummi_cgm_meals, gummi_cgm, linear_regression_cgm, persistence, mean), horizon_min INT, window STRING (all, meal, quiet), rmse_mean, rmse_sd, mae_mean, coverage DOUBLE, n BIGINT |
| ablation_results | comparison STRING, horizon_min INT, window STRING, rmse_a, rmse_b, diff_mean, diff_sd DOUBLE, folds_b_better INT, folds INT |
| breakfast_response | participant_id STRING, n INT, carbs_g_mean, rise_mean_mg_dl, rise_sd_mg_dl, rise_min_mg_dl, rise_max_mg_dl, time_to_peak_min, rise_per_g DOUBLE, overlapped INT |
| ablation_hr (new) | same columns as ablation_results |
| meal_prediction_eval (new) | fold INT, participant_id, meal_id, model STRING, carbs_g DOUBLE, is_standard_breakfast BOOLEAN, predicted_peak, actual_peak, last_value, peak_abs_err, last_value_peak_abs_err, curve_mae, last_value_curve_mae DOUBLE |
| meal_prediction_summary (new) | model STRING, meals INT, peak_mae, last_value_peak_mae, peak_bias, curve_mae, last_value_curve_mae, gummi_beats_last_value_pct DOUBLE, subset STRING |
| baseline_repro (new) | fold INT, model STRING, n_test INT, test_participants STRING, rmse, mae DOUBLE |
| completeness (new) | participant_id STRING, days, readings INT, glucose_mean, glucose_sd, glucose_min, glucose_max, biggest_gap_min DOUBLE, islands, low_high_flags INT, completeness DOUBLE, gender STRING, hba1c DOUBLE |
