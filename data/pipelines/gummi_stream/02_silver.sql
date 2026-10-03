-- gummi_stream, silver layer: one streaming table per event kind (CONTRACT.md section 10).
-- Events can be re-sent (for example an edited meal); gold views keep the newest row per id.

CREATE OR REFRESH STREAMING TABLE stream_silver_cgm (
  CONSTRAINT dexcom_range EXPECT (glucose_mg_dl BETWEEN 40 AND 400) ON VIOLATION DROP ROW
)
COMMENT 'Confirmed CGM readings (replayed BIG IDEAs, Dexcom sandbox). t = reading time, released_at = when the App released it (the 60-minute delay).'
AS SELECT
  event_id,
  user_id,
  source,
  t,
  released_at,
  payload:glucose_mg_dl::DOUBLE AS glucose_mg_dl,
  landed_at,
  ingested_at
FROM STREAM stream_bronze_events
WHERE kind = 'cgm';

CREATE OR REFRESH STREAMING TABLE stream_silver_meals
COMMENT 'Logged meals (chat, manual, replayed food logs). Newest row per meal_id wins after edits.'
AS SELECT
  event_id,
  user_id,
  source,
  payload:meal_id::STRING AS meal_id,
  try_cast(payload:eaten_at::STRING AS TIMESTAMP) AS eaten_at,
  payload:source::STRING AS meal_source,
  payload:totals.carbs_g::DOUBLE AS carbs_g,
  payload:totals.sugar_g::DOUBLE AS sugar_g,
  payload:totals.fiber_g::DOUBLE AS fiber_g,
  payload:totals.protein_g::DOUBLE AS protein_g,
  payload:totals.fat_g::DOUBLE AS fat_g,
  payload:totals.calories::DOUBLE AS calories,
  payload:items AS items,
  payload:prediction_id::STRING AS prediction_id,
  released_at,
  ingested_at
FROM STREAM stream_bronze_events
WHERE kind = 'meal';

CREATE OR REFRESH STREAMING TABLE stream_silver_predictions
COMMENT 'Gummi predictions (meal and nowcast) with the CGM-only and last-value peaks stored next to them (v1.1).'
AS SELECT
  event_id,
  user_id,
  payload:prediction_id::STRING AS prediction_id,
  payload:kind::STRING AS prediction_kind,
  try_cast(payload:made_at::STRING AS TIMESTAMP) AS made_at,
  payload:about::STRING AS about,
  payload:meal_id::STRING AS meal_id,
  try_cast(payload:window_start::STRING AS TIMESTAMP) AS window_start,
  try_cast(payload:window_end::STRING AS TIMESTAMP) AS window_end,
  payload:predicted_peak_mg_dl::DOUBLE AS predicted_peak_mg_dl,
  payload:cgm_only_peak_mg_dl::DOUBLE AS cgm_only_peak_mg_dl,
  payload:last_value_peak_mg_dl::DOUBLE AS last_value_peak_mg_dl,
  payload:status::STRING AS status,
  payload:predicted_curve AS predicted_curve,
  released_at,
  ingested_at
FROM STREAM stream_bronze_events
WHERE kind = 'prediction';

CREATE OR REFRESH STREAMING TABLE stream_silver_grades (
  CONSTRAINT has_errors EXPECT (gummi_mae_mg_dl IS NOT NULL AND last_value_mae_mg_dl IS NOT NULL)
)
COMMENT 'Grades: Gummi, CGM-only and last-value errors over the same closed window (v1.1). walk_effect_graded false = a phone walk overlapped replayed data (D-28).'
AS SELECT
  event_id,
  user_id,
  payload:grade_id::STRING AS grade_id,
  payload:prediction_id::STRING AS prediction_id,
  payload:kind::STRING AS grade_kind,
  try_cast(payload:graded_at::STRING AS TIMESTAMP) AS graded_at,
  payload:points::INT AS points,
  payload:gummi_mae_mg_dl::DOUBLE AS gummi_mae_mg_dl,
  payload:cgm_only_mae_mg_dl::DOUBLE AS cgm_only_mae_mg_dl,
  payload:last_value_mae_mg_dl::DOUBLE AS last_value_mae_mg_dl,
  payload:gummi_peak_error_mg_dl::DOUBLE AS gummi_peak_error_mg_dl,
  payload:within_band_pct::DOUBLE AS within_band_pct,
  COALESCE(payload:walk_effect_graded::BOOLEAN, true) AS walk_effect_graded,
  payload:message::STRING AS message,
  payload:gummi_mae_mg_dl::DOUBLE < payload:cgm_only_mae_mg_dl::DOUBLE AS gummi_beats_cgm_only,
  payload:gummi_mae_mg_dl::DOUBLE < payload:last_value_mae_mg_dl::DOUBLE AS gummi_beats_last_value,
  released_at,
  ingested_at
FROM STREAM stream_bronze_events
WHERE kind = 'grade';

CREATE OR REFRESH STREAMING TABLE stream_silver_cards
COMMENT 'Story cards posted to Today and Home, by the event-driven agent or templates.'
AS SELECT
  event_id,
  user_id,
  payload:card_id::STRING AS card_id,
  payload:type::STRING AS card_type,
  try_cast(payload:created_at::STRING AS TIMESTAMP) AS created_at,
  payload:title::STRING AS title,
  payload:body::STRING AS body,
  payload:mood::STRING AS mood,
  payload:generated_by::STRING AS generated_by,
  payload:trace_id::STRING AS trace_id,
  released_at,
  ingested_at
FROM STREAM stream_bronze_events
WHERE kind = 'card';
