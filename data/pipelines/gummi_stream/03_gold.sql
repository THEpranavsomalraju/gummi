-- gummi_stream, gold layer: materialized views for the fleet view and the honest-accuracy story (v1.1).
-- Every accuracy number carries Gummi, CGM-only and last value. Replay participants (p_*) are predicted by the fold
-- model that never saw them, so their rows are labeled out-of-sample (D-26). Windows where a phone walk overlapped
-- replayed glucose (walk_effect_graded false, D-28) are left out. Window types:
--   meal  = a meal prediction, or a nowcast grade whose window starts within 180 minutes after a logged meal
--   quiet = everything else (quiet periods flatter any method, so they are reported separately)

CREATE OR REFRESH MATERIALIZED VIEW stream_gold_accuracy
COMMENT 'Gummi vs CGM-only vs last value by sample (out-of-sample for replay participants, live for teammates), participant and window type. user_id ALL and window_type all are rollups. Read by /fleet and get_gold_summary.'
AS
WITH grades AS (
  SELECT * FROM stream_silver_grades
  QUALIFY ROW_NUMBER() OVER (PARTITION BY grade_id ORDER BY ingested_at DESC) = 1
),
preds AS (
  SELECT * FROM stream_silver_predictions
  QUALIFY ROW_NUMBER() OVER (PARTITION BY prediction_id ORDER BY ingested_at DESC) = 1
),
meals AS (
  SELECT * FROM stream_silver_meals
  QUALIFY ROW_NUMBER() OVER (PARTITION BY meal_id ORDER BY ingested_at DESC) = 1
),
meal_hits AS (
  SELECT g.grade_id, COUNT(m.meal_id) AS meals_near
  FROM grades g
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
  FROM grades g
  JOIN meal_hits h ON g.grade_id = h.grade_id
  WHERE g.walk_effect_graded
)
SELECT
  sample,
  COALESCE(user_id, 'ALL') AS user_id,
  COALESCE(window_type, 'all') AS window_type,
  COUNT(*) AS grades,
  ROUND(AVG(gummi_mae_mg_dl), 1) AS gummi_mae_mg_dl,
  ROUND(AVG(cgm_only_mae_mg_dl), 1) AS cgm_only_mae_mg_dl,
  ROUND(AVG(last_value_mae_mg_dl), 1) AS last_value_mae_mg_dl,
  ROUND(100.0 * AVG(CASE WHEN gummi_beats_cgm_only THEN 1.0 WHEN NOT gummi_beats_cgm_only THEN 0.0 END), 1) AS gummi_beats_cgm_only_pct,
  ROUND(100.0 * AVG(CASE WHEN gummi_beats_last_value THEN 1.0 WHEN NOT gummi_beats_last_value THEN 0.0 END), 1) AS gummi_beats_last_value_pct,
  ROUND(AVG(gummi_peak_error_mg_dl), 1) AS gummi_peak_error_mg_dl,
  ROUND(AVG(within_band_pct), 1) AS within_band_pct,
  MAX(graded_at) AS last_graded_at
FROM typed
GROUP BY GROUPING SETS ((sample, user_id, window_type), (sample, user_id), (sample, window_type), (sample));

CREATE OR REFRESH MATERIALIZED VIEW stream_gold_fleet
COMMENT 'One row per streaming user for the fleet view: newest confirmed reading, grades, Gummi vs CGM-only vs last-value error (walk-overlapped windows left out), latest card, pipeline lag.'
AS
WITH cgm AS (
  SELECT
    user_id,
    MAX(t) AS data_through,
    MAX_BY(glucose_mg_dl, t) AS last_glucose_mg_dl,
    COUNT(*) AS readings,
    -- released_at runs on the replay clock, so lag is measured on wall time: file landed -> row ingested
    ROUND(AVG(CASE WHEN ingested_at >= current_timestamp() - INTERVAL 10 MINUTES
                   THEN unix_timestamp(ingested_at) - unix_timestamp(landed_at) END), 1) AS pipeline_lag_seconds
  FROM stream_silver_cgm
  GROUP BY user_id
),
g AS (
  SELECT
    user_id,
    COUNT(*) AS grades,
    ROUND(AVG(CASE WHEN walk_effect_graded THEN gummi_mae_mg_dl END), 1) AS gummi_mae_mg_dl,
    ROUND(AVG(CASE WHEN walk_effect_graded THEN cgm_only_mae_mg_dl END), 1) AS cgm_only_mae_mg_dl,
    ROUND(AVG(CASE WHEN walk_effect_graded THEN last_value_mae_mg_dl END), 1) AS last_value_mae_mg_dl,
    MAX_BY(message, graded_at) AS last_grade_message,
    MAX(graded_at) AS last_graded_at
  FROM (
    SELECT * FROM stream_silver_grades
    QUALIFY ROW_NUMBER() OVER (PARTITION BY grade_id ORDER BY ingested_at DESC) = 1
  )
  GROUP BY user_id
),
c AS (
  SELECT
    user_id,
    MAX_BY(card_type, created_at) AS last_card_type,
    MAX_BY(title, created_at) AS last_card_title,
    MAX(created_at) AS last_card_at
  FROM stream_silver_cards
  GROUP BY user_id
)
SELECT
  cgm.user_id,
  cgm.data_through,
  cgm.last_glucose_mg_dl,
  cgm.readings,
  COALESCE(g.grades, 0) AS grades,
  CASE WHEN left(cgm.user_id, 2) = 'p_' THEN 'out-of-sample' ELSE 'live' END AS sample,
  g.gummi_mae_mg_dl,
  g.cgm_only_mae_mg_dl,
  g.last_value_mae_mg_dl,
  g.last_grade_message,
  g.last_graded_at,
  c.last_card_type,
  c.last_card_title,
  c.last_card_at,
  cgm.pipeline_lag_seconds
FROM cgm
LEFT JOIN g ON cgm.user_id = g.user_id
LEFT JOIN c ON cgm.user_id = c.user_id;
