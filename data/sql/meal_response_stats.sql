-- UC function for the Gummi Insights supervisor (D-52): how each logged meal went for one user.
-- Actual rise = highest confirmed reading 0 to 120 minutes after eating minus the last reading at or before eating.
-- Errors come from the meal prediction's grade (Gummi, CGM-only, last value), when it has been graded.
CREATE OR REPLACE FUNCTION workspace.gummi_data.meal_response_stats(
  user_id STRING COMMENT 'Gummi user id: p_012 style for replay participants, u_<name> for teammates, or ALL for everyone'
)
RETURNS TABLE (
  user_id STRING COMMENT 'The user',
  meal_id STRING COMMENT 'Meal id',
  eaten_at TIMESTAMP COMMENT 'When the meal was eaten (replay clock for p_ users)',
  about STRING COMMENT 'What the prediction called the meal',
  carbs_g DOUBLE COMMENT 'Carbohydrates, grams',
  sugar_g DOUBLE COMMENT 'Sugar, grams',
  glucose_before_mg_dl DOUBLE COMMENT 'Last confirmed reading at or before eating, mg/dL',
  actual_peak_mg_dl DOUBLE COMMENT 'Highest confirmed reading 0 to 120 minutes after eating, mg/dL',
  actual_rise_mg_dl DOUBLE COMMENT 'actual_peak_mg_dl minus glucose_before_mg_dl',
  readings_in_window BIGINT COMMENT 'Confirmed readings 0 to 120 minutes after eating (24 is complete)',
  predicted_peak_mg_dl DOUBLE COMMENT 'Gummi predicted peak at logging time, mg/dL',
  cgm_only_peak_mg_dl DOUBLE COMMENT 'CGM-only baseline peak at logging time, mg/dL',
  last_value_peak_mg_dl DOUBLE COMMENT 'Last-value guess at logging time, mg/dL',
  gummi_mae_mg_dl DOUBLE COMMENT 'Gummi curve error over the 2-hour window, mg/dL (NULL until graded)',
  cgm_only_mae_mg_dl DOUBLE COMMENT 'CGM-only curve error, mg/dL',
  last_value_mae_mg_dl DOUBLE COMMENT 'Last-value curve error, mg/dL',
  gummi_peak_error_mg_dl DOUBLE COMMENT 'Gummi peak error, mg/dL',
  gummi_beats_cgm_only BOOLEAN COMMENT 'Gummi closer than CGM-only over the window',
  walk_effect_graded BOOLEAN COMMENT 'False when a phone walk overlapped replayed data (left out of accuracy)'
)
COMMENT 'Per-meal response for one user: carbs, actual rise and peak, Gummi predicted peak, and the Gummi, CGM-only and last-value errors once graded. Read-only; mg/dL; not for treatment decisions.'
RETURN
WITH meals AS (
  SELECT * FROM workspace.gummi_data.stream_silver_meals
  WHERE meal_response_stats.user_id = 'ALL' OR user_id = meal_response_stats.user_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY meal_id ORDER BY ingested_at DESC) = 1
),
preds AS (
  SELECT * FROM workspace.gummi_data.stream_silver_predictions
  WHERE prediction_kind = 'meal'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY prediction_id ORDER BY ingested_at DESC) = 1
),
grades AS (
  SELECT * FROM workspace.gummi_data.stream_silver_grades
  QUALIFY ROW_NUMBER() OVER (PARTITION BY grade_id ORDER BY ingested_at DESC) = 1
),
cgm AS (
  SELECT user_id, t, glucose_mg_dl FROM workspace.gummi_data.stream_silver_cgm
  WHERE meal_response_stats.user_id = 'ALL' OR user_id = meal_response_stats.user_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id, t ORDER BY ingested_at DESC) = 1
),
resp AS (
  SELECT
    m.meal_id,
    MAX_BY(CASE WHEN c.t <= m.eaten_at THEN c.glucose_mg_dl END, CASE WHEN c.t <= m.eaten_at THEN c.t END) AS glucose_before,
    MAX(CASE WHEN c.t > m.eaten_at AND c.t <= m.eaten_at + INTERVAL 120 MINUTES THEN c.glucose_mg_dl END) AS actual_peak,
    COUNT(CASE WHEN c.t > m.eaten_at AND c.t <= m.eaten_at + INTERVAL 120 MINUTES THEN 1 END) AS n_after
  FROM meals m
  JOIN cgm c ON c.user_id = m.user_id AND c.t BETWEEN m.eaten_at - INTERVAL 30 MINUTES AND m.eaten_at + INTERVAL 120 MINUTES
  GROUP BY m.meal_id
)
SELECT
  m.user_id, m.meal_id, m.eaten_at, p.about, m.carbs_g, m.sugar_g,
  r.glucose_before AS glucose_before_mg_dl,
  r.actual_peak AS actual_peak_mg_dl,
  CAST(ROUND(r.actual_peak - r.glucose_before, 1) AS DOUBLE) AS actual_rise_mg_dl,
  COALESCE(r.n_after, 0) AS readings_in_window,
  p.predicted_peak_mg_dl, p.cgm_only_peak_mg_dl, p.last_value_peak_mg_dl,
  g.gummi_mae_mg_dl, g.cgm_only_mae_mg_dl, g.last_value_mae_mg_dl, g.gummi_peak_error_mg_dl,
  g.gummi_beats_cgm_only, g.walk_effect_graded
FROM meals m
LEFT JOIN preds p ON p.prediction_id = COALESCE(m.prediction_id, concat('pr_', substr(m.meal_id, 3)))
LEFT JOIN grades g ON g.prediction_id = p.prediction_id
LEFT JOIN resp r ON r.meal_id = m.meal_id
ORDER BY m.user_id, m.eaten_at
