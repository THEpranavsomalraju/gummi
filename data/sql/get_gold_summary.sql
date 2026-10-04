-- UC function for the Gummi Insights supervisor and the evening_recap tool (CONTRACT section 7, D-52).
-- Same rules as stream_gold_accuracy (03_gold.sql), recomputed over a time window so "today" works:
-- Gummi vs CGM-only vs last value, replay participants labeled out-of-sample, walk-overlapped windows left out.
-- Rows: every rollup for the asked user, plus the out-of-sample all-participants rollup (user_id ALL).
CREATE OR REPLACE FUNCTION workspace.gummi_data.get_gold_summary(
  user_id STRING COMMENT 'Gummi user id: p_012 style for replay participants, u_<name> for teammates, or ALL for only the fleet rollup',
  days INT DEFAULT 1 COMMENT 'Calendar days back on the replay clock, counting today as 1. 0 or NULL means all time.'
)
RETURNS TABLE (
  sample STRING COMMENT 'out-of-sample for replay participants (predicted by a fold model that never saw them), live for teammates',
  user_id STRING COMMENT 'The user, or ALL for the rollup over every user in the sample',
  window_type STRING COMMENT 'meal, quiet, or all',
  grades BIGINT COMMENT 'Graded predictions in the window',
  gummi_mae_mg_dl DOUBLE COMMENT 'Gummi mean absolute error, mg/dL',
  cgm_only_mae_mg_dl DOUBLE COMMENT 'CGM-only linear baseline (published method) mean absolute error, mg/dL',
  last_value_mae_mg_dl DOUBLE COMMENT 'Last-value guess mean absolute error, mg/dL',
  gummi_beats_cgm_only_pct DOUBLE COMMENT 'Percent of grades where Gummi beat CGM-only',
  gummi_beats_last_value_pct DOUBLE COMMENT 'Percent of grades where Gummi beat the last value',
  gummi_peak_error_mg_dl DOUBLE COMMENT 'Mean absolute error of the predicted peak, mg/dL',
  within_band_pct DOUBLE COMMENT 'Percent of readings inside Gummi''s band',
  last_graded_at TIMESTAMP COMMENT 'Newest grade in the window (replay clock)'
)
COMMENT 'Gummi accuracy summary for one user over the last N days next to the CGM-only and last-value baselines, plus the out-of-sample fleet rollup. Read-only; numbers in mg/dL; not for treatment decisions.'
RETURN
WITH grades AS (
  SELECT * FROM workspace.gummi_data.stream_silver_grades
  QUALIFY ROW_NUMBER() OVER (PARTITION BY grade_id ORDER BY ingested_at DESC) = 1
),
preds AS (
  SELECT * FROM workspace.gummi_data.stream_silver_predictions
  QUALIFY ROW_NUMBER() OVER (PARTITION BY prediction_id ORDER BY ingested_at DESC) = 1
),
meals AS (
  SELECT * FROM workspace.gummi_data.stream_silver_meals
  QUALIFY ROW_NUMBER() OVER (PARTITION BY meal_id ORDER BY ingested_at DESC) = 1
),
recent AS (
  SELECT * FROM grades
  WHERE walk_effect_graded
    AND (COALESCE(get_gold_summary.days, 0) <= 0
         OR graded_at >= CAST(date_sub(current_date(), get_gold_summary.days - 1) AS TIMESTAMP))
),
meal_hits AS (
  SELECT g.grade_id, COUNT(m.meal_id) AS meals_near
  FROM recent g
  LEFT JOIN preds p ON g.prediction_id = p.prediction_id
  LEFT JOIN meals m
    ON m.user_id = g.user_id
   AND m.eaten_at BETWEEN p.window_start - INTERVAL 180 MINUTES AND p.window_end
  GROUP BY g.grade_id
),
typed AS (
  SELECT
    g.*,
    CASE WHEN g.grade_kind = 'meal' OR h.meals_near > 0 THEN 'meal' ELSE 'quiet' END AS window_type,
    CASE WHEN left(g.user_id, 2) = 'p_' THEN 'out-of-sample' ELSE 'live' END AS sample
  FROM recent g
  JOIN meal_hits h ON g.grade_id = h.grade_id
),
rolled AS (
  SELECT
    sample,
    COALESCE(user_id, 'ALL') AS uid,
    COALESCE(window_type, 'all') AS window_type,
    COUNT(*) AS grades,
    CAST(ROUND(AVG(gummi_mae_mg_dl), 1) AS DOUBLE) AS gummi_mae_mg_dl,
    CAST(ROUND(AVG(cgm_only_mae_mg_dl), 1) AS DOUBLE) AS cgm_only_mae_mg_dl,
    CAST(ROUND(AVG(last_value_mae_mg_dl), 1) AS DOUBLE) AS last_value_mae_mg_dl,
    CAST(ROUND(100.0 * AVG(CASE WHEN gummi_beats_cgm_only THEN 1.0 WHEN NOT gummi_beats_cgm_only THEN 0.0 END), 1) AS DOUBLE) AS gummi_beats_cgm_only_pct,
    CAST(ROUND(100.0 * AVG(CASE WHEN gummi_beats_last_value THEN 1.0 WHEN NOT gummi_beats_last_value THEN 0.0 END), 1) AS DOUBLE) AS gummi_beats_last_value_pct,
    CAST(ROUND(AVG(gummi_peak_error_mg_dl), 1) AS DOUBLE) AS gummi_peak_error_mg_dl,
    CAST(ROUND(AVG(within_band_pct), 1) AS DOUBLE) AS within_band_pct,
    MAX(graded_at) AS last_graded_at
  FROM typed
  GROUP BY GROUPING SETS ((sample, user_id, window_type), (sample, user_id), (sample, window_type), (sample))
)
SELECT sample, uid AS user_id, window_type, grades, gummi_mae_mg_dl, cgm_only_mae_mg_dl, last_value_mae_mg_dl,
       gummi_beats_cgm_only_pct, gummi_beats_last_value_pct, gummi_peak_error_mg_dl, within_band_pct, last_graded_at
FROM rolled
WHERE uid = get_gold_summary.user_id
   OR (sample = 'out-of-sample' AND uid = 'ALL')
ORDER BY CASE WHEN uid = 'ALL' THEN 1 ELSE 0 END, sample, window_type
