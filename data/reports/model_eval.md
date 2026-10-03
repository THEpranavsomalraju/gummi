# gummi_model v1: evaluation

DRAFT, Data Lead. Not judge-facing until the human approves the numbers (hard stop). Every number comes from
`gummi_pipeline.run` (the same code locally and in the Databricks job `gummi_data_load_train`; both give the same
results) and lands in `workspace.gummi_ml` tables and the MLflow experiment `/Shared/gummi_model`.

## Setup

- Data: 15 BIG IDEAs participants (015 excluded, D-20), 34,466 forecast origins (every reading with 24 readings of
  history inside a gap-free island).
- Validation: participant-grouped 5-fold CV with the same folds as the published-baseline reproduction. No person is
  ever in train and test (`tests/test_baseline_no_leakage.py`).
- Model: one ridge regression per 5-minute horizon on the change from the last reading. Features: the last 24
  readings, slopes, curvature, time of day, the 24-hour mean, and meal features (carbs, sugar, fiber, protein, fat
  through gamma absorption kernels, minutes since the meal). Bands: 10th and 90th percentiles of out-of-fold
  residuals, separately for meal and quiet windows.
- Horizons count from the last confirmed reading. With the 60-minute Dexcom delay, "now" is horizon 60 and the
  2-hour forecast runs to horizon 180.
- Meal window: the target falls within 180 minutes after a logged meal. Quiet: everything else.
- Shipped artifact (v1.1, D-26): the full model plus the 5 fold models from this CV and the participant-to-fold map.
  Replay participants are always served by the fold that never saw them, so live replay grades are out-of-sample
  like the numbers here. Each fold also carries the CGM-only linear models (D-33) for the live three-way grades.

## 1. Forecast error by horizon (RMSE mg/dL, mean +/- SD over 5 folds)

| Horizon | Gummi (CGM + meals) | Gummi without meals (ablation) | CGM-only (published linear method, D-33) | Last value | Mean |
|---|---|---|---|---|---|
| 30 min | 13.26 +/- 1.10 | 13.70 +/- 0.60 | 13.90 +/- 0.65 | 16.49 +/- 0.97 | 23.37 |
| 60 min | 17.98 +/- 2.21 | 18.84 +/- 1.68 | 19.41 +/- 1.93 | 22.50 +/- 2.08 | 23.39 |
| 90 min | 19.28 +/- 2.57 | 20.27 +/- 2.19 | 21.12 +/- 2.62 | 25.22 +/- 3.01 | 23.40 |
| 120 min | 20.42 +/- 2.29 | 20.85 +/- 2.31 | 21.93 +/- 2.91 | 27.09 +/- 3.28 | 23.37 |
| 180 min | 21.16 +/- 2.12 | 21.18 +/- 2.23 | 22.53 +/- 3.07 | 28.83 +/- 3.41 | 23.38 |

Meal windows versus quiet windows (RMSE mg/dL):

| Horizon | Window | Gummi | CGM-only | Last value |
|---|---|---|---|---|
| 60 min | meal | 22.36 | 24.13 | 28.36 |
| 60 min | quiet | 12.13 | 13.04 | 14.31 |
| 120 min | meal | 25.01 | 26.52 | 32.47 |
| 120 min | quiet | 14.48 | 16.06 | 20.19 |

Reading it: Gummi beats every baseline at every horizon up to 120 minutes. At 120 to 180 minutes everything drifts
toward the cohort mean (23.4), as DATA_NOTES warned for this flat cohort. Meal windows are about twice as hard as
quiet ones.

## 2. Do logged meals help? (meal ablation, same ridge with and without meal features)

| Horizon | All windows: RMSE change | Folds better | Meal windows: RMSE change | Folds better |
|---|---|---|---|---|
| 30 min | -0.44 (SD 0.60) | 4 of 5 | -0.57 (SD 0.97) | 4 of 5 |
| 60 min | -0.86 (SD 1.43) | 4 of 5 | -1.13 (SD 2.19) | 4 of 5 |
| 90 min | -0.98 (SD 1.78) | 4 of 5 | -1.26 (SD 2.74) | 4 of 5 |
| 120 min | -0.43 (SD 1.28) | 4 of 5 | -0.37 (SD 2.11) | 4 of 5 |
| 180 min | -0.02 (SD 0.29) | 3 of 5 | +0.03 (SD 0.49) | 3 of 5 |

Answer: yes, a small gain from 30 to 120 minutes in 4 of 5 folds, nothing at 180. The fold without a gain holds
participants 002 and 016, whose rises do not track carbs at all (Spearman -0.02 and -0.29). So the model method is
"model", not the breakfast-response fallback. Heart rate added nothing (phase1_findings.md section 6).

## 3. Band coverage (target 80%)

All windows: 0.80 at every horizon. Quiet windows: 0.80 to 0.85. Meal windows: 0.80 at 30 to 60 minutes, 0.79 at 90,
0.76 at 120, 0.74 at 180. After meals the band is slightly too narrow at long horizons.

## 4. What the app does: predicting a meal when it is logged

Each held-out meal, predicted at the moment it is logged with readings only up to one hour before (the Dexcom
delay), graded over the next 2 hours against what happened. The last-value guess is the last reading Gummi had.

| Meals | Model | Peak error | Peak error, last value | Signed peak error | Curve error | Curve error, last value | Curve beats last value |
|---|---|---|---|---|---|---|---|
| All 602 | Gummi (CGM + meals) | 22.7 | 35.1 | -14.4 | 18.3 | 23.2 | 66.8% |
| All 602 | Gummi without meals (ablation) | 28.1 | 35.1 | -25.2 | 18.6 | 23.2 | 63.6% |
| All 602 | CGM-only (published linear, D-33) | 28.9 | 35.1 | -25.3 | 19.3 | 23.2 | 64.1% |
| 282 with 40 g+ carbs | Gummi (CGM + meals) | 28.0 | 44.4 | -16.1 | 22.4 | 27.5 | 70.6% |
| 282 with 40 g+ carbs | Gummi without meals (ablation) | 37.5 | 44.4 | -35.9 | 22.5 | 27.5 | 66.7% |
| 282 with 40 g+ carbs | CGM-only (published linear, D-33) | 37.9 | 44.4 | -35.8 | 23.1 | 27.5 | 71.3% |
| 59 standardized breakfasts | Gummi (CGM + meals) | 42.5 | 56.5 | -40.3 | 26.9 | 32.2 | 89.8% |
| 59 standardized breakfasts | Gummi without meals (ablation) | 55.4 | 56.5 | -54.9 | 31.7 | 32.2 | 49.2% |
| 59 standardized breakfasts | CGM-only (published linear, D-33) | 53.5 | 56.5 | -52.5 | 30.9 | 32.2 | 59.3% |

(errors in mg/dL, mean absolute; signed = predicted minus actual peak. Two food-log rows that logged fat equal to
calories are repaired from the calories before training, bigideas/silver.py.) Logging the meal cuts the peak error by
about 5 mg/dL overall and 13 mg/dL for the standardized breakfast, and the peak gain shows in all 5 folds.

The weak spot, stated plainly: Gummi predicts peaks too low, by 14 mg/dL on average and by 40 mg/dL after the
sugary standardized breakfast. A ridge model on 15 people learns the average response, and big individual spikes sit
far above it. Scaling every meal's effect up by one cohort-wide factor does not fix it (peak error down by
about 0.9 mg/dL at best, curve error worse), because the needed scale differs by person and by meal.

## 5. Personal layer (learned online from the person's own earlier meals)

Same 602 meals as section 4, in time order per person. Before each meal, the person's carb factor (how strongly they
respond compared with the population model) and offset are fitted only on their own earlier meals whose 2-hour
window had closed and whose readings had arrived. The population model never saw the person.

| Meals | Variant | Peak error | Signed peak error | Curve error | Median carb factor |
|---|---|---|---|---|---|
| All 602 | none | 22.7 | -14.4 | 18.3 | 1.00 |
| All 602 | carb factor | 21.4 | -11.1 | 18.5 | 1.26 |
| All 602 | carb factor + offset | 21.3 | -11.8 | 18.5 | 1.28 |
| 524 after 5+ earlier meals | none | 22.8 | -14.4 | 18.6 | 1.00 |
| 524 after 5+ earlier meals | carb factor + offset | 21.0 | -11.5 | 18.6 | 1.30 |
| 59 standardized breakfasts | none | 42.5 | -40.3 | 26.9 | 1.00 |
| 59 standardized breakfasts | carb factor + offset | 39.7 | -37.5 | 26.2 | 0.91 |

Answer: the personal layer helps a little and the right way. Peak error drops by 1.4 to 1.8 mg/dL (6 to 8%) once
a person has a few closed meals, the under-prediction shrinks, and the curve error stays within 0.3 mg/dL. Most
people respond more strongly than the population model (median factor 1.28). `update_personal` now fits the factor
and the offset together on the person's meals, the variant measured here (D-48).

## 6. Speed (CONTRACT.md section 8 budgets)

On a real history of 1,501 readings and 18 meals: estimate plus forecast 17.6 ms (budget 50), gummi_view 11.7 ms,
simulate 44.4 ms (budget 100). numpy and pandas only.

## Limits to say out loud

15 people, all with normal to prediabetic HbA1c, about 9 days each; self-reported food logs with errors (one meal
logs 463 g carbs, one coffee 70 g); time stamps of meals as logged; the cohort is flat, so long horizons drift to the
mean; peaks of big spikes are under-predicted; the walk effect comes from the literature, not from this data.
