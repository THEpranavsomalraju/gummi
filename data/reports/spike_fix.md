# Big-spike fix: the big-meal term (D-70)

DRAFT, Data Lead, 2026-10-03. Asked for by Backend (REQUEST 2010, ask B). Pranav and Nikhil approve any number
before it is judge-facing.

## The problem

Gummi predicted the peaks of big meals too low: by 14.4 mg/dL on average and by 40.3 mg/dL after the sugary
standardized breakfast. That cost the demo twice. The forecast crossed 140 less often than real glucose did, so the
walk nudge fired less. And "I predicted 168, it was 172" landed less often on big meals.

## What changed

One new meal feature, `carbs_big_g`: the meal's carbs above 40 g, on the same absorption kernel as carbs. Each
horizon's ridge can then give big meals a steeper rise than small ones. It is a hinge, so the carb response is
piecewise linear.

The term is ramped out between 150 and 180 minutes after the last reading. Up to 150 minutes the model uses it
fully. From 180 minutes the model is exactly the v1.1 one: the column is zeroed, so its weight is 0. In between,
the two models are blended linearly, and the blend is saved as one linear model, so the forecast curve has no step.

The interface is unchanged (for_user, cgm_only_forecast, grade, simulate). The artifact does need the updated
gummi_model code, because the code derives the new column. Until the App ships that code, the new artifact waits at
/Volumes/workspace/gummi_ml/artifacts/gummi_model_v1_next/ (registered model version 5), and gummi_model_v1/ keeps
v1.1. The new code also loads the v1.1 artifact, so the App can update its code first and switch artifacts second.

## What was tried (participant-grouped, same 5 folds, fit out-of-fold)

| Variant | MAE 60 min, all | MAE 180 min, all | Peak bias, all meals | Peak bias, std breakfast | Meals reaching 140 caught |
|---|---|---|---|---|---|
| v1.1 (before) | 12.35 | 15.15 | -14.4 | -40.3 | 93 of 292 |
| carbs hinge at 40 g (everywhere) | 12.06 | 15.17 | -10.7 | -31.4 | 134 |
| carbs hinge at 30 g | 12.10 | 15.18 | -10.9 | -33.6 | 135 |
| carbs hinge at 60 g | 12.05 | 15.18 | -11.0 | -28.5 | 140 |
| carbs plus sugar hinges | 12.07 | 15.19 | -10.9 | -32.3 | 135 |
| fast and slow carb kernels (no hinge) | 12.26 | 15.15 | -15.8 | -41.7 | 86 |
| fast and slow kernels plus hinges | 12.00 | 15.18 | -11.2 | -31.4 | 139 |
| **carbs hinge at 40 g, ramped out 150 to 180 min (shipped)** | **12.06** | **15.15** | **-10.7** | **-31.4** | **135** |

- Option (b), a nonlinear carb term, is what worked.
- Option (a), a carb-conditioned bias correction, adds nothing a hinge does not. A linear correction on the carb
  features is absorbed by the ridge itself, and a binned one is a coarser hinge.
- Option (c), an asymmetric or quantile loss, was not tried. It raises peaks by giving up MAE everywhere, which
  breaks the ship rule.
- Every hinge-everywhere variant cost 0.02 to 0.04 mg/dL at 180 minutes, which is noise but fails "keep or improve
  at every horizon". The ramp keeps 180 identical.
- How far the term should reach was checked with nested CV: for each outer fold, an inner participant-grouped CV
  on that fold's training people only. The picks were 135, 150, 150, 135 and "everywhere", and all the
  candidates sat within 0.01 mg/dL of each other. On all 15 people the pick is 150 minutes.
- Code: data/scripts/spike_experiment.py and data/scripts/spike_select_cutoff.py.

## Before and after: forecast error (mg/dL, participant-grouped, 5-fold mean)

"Folds better" counts the folds where Gummi's MAE went down. Horizons count from the last confirmed reading, so
"now" is 60 and the 2-hour forecast ends at 180.

| Window | Horizon | Gummi MAE before | Gummi MAE after | Folds better | CGM-only MAE | Last value MAE | RMSE before | RMSE after (fold SD) | Band coverage before / after |
|---|---|---|---|---|---|---|---|---|---|
| all | 30 min | 9.04 | 8.90 | 5 of 5 | 9.48 | 10.68 | 13.26 | 12.99 (0.98) | 0.80 / 0.80 |
| all | 60 min | 12.35 | 12.06 | 5 of 5 | 13.42 | 14.87 | 17.98 | 17.48 (2.06) | 0.80 / 0.80 |
| all | 90 min | 13.46 | 13.15 | 5 of 5 | 14.92 | 16.91 | 19.28 | 18.80 (2.48) | 0.80 / 0.80 |
| all | 120 min | 14.37 | 14.24 | 4 of 5 | 15.73 | 18.42 | 20.42 | 20.19 (2.29) | 0.80 / 0.80 |
| all | 180 min | 15.15 | 15.15 | equal in 5 of 5 | 16.41 | 20.10 | 21.16 | 21.16 (2.12) | 0.80 / 0.80 |
| meal | 30 min | 11.71 | 11.48 | 5 of 5 | 12.14 | 14.61 | 16.27 | 15.84 (1.05) | 0.80 / 0.80 |
| meal | 60 min | 16.20 | 15.72 | 5 of 5 | 17.33 | 20.36 | 22.36 | 21.58 (2.45) | 0.80 / 0.80 |
| meal | 90 min | 17.28 | 16.82 | 5 of 5 | 18.84 | 22.63 | 23.75 | 23.04 (2.98) | 0.79 / 0.79 |
| meal | 120 min | 18.08 | 17.89 | 4 of 5 | 19.31 | 23.61 | 25.01 | 24.68 (2.69) | 0.76 / 0.76 |
| meal | 180 min | 18.48 | 18.48 | equal in 5 of 5 | 19.51 | 24.13 | 25.50 | 25.50 (2.81) | 0.74 / 0.74 |
| quiet | 30 min | 6.39 | 6.35 | 5 of 5 | 6.83 | 6.77 | 9.30 | 9.26 (1.76) | 0.80 / 0.80 |
| quiet | 60 min | 8.56 | 8.47 | 5 of 5 | 9.54 | 9.41 | 12.13 | 12.05 (2.61) | 0.81 / 0.81 |
| quiet | 90 min | 9.71 | 9.56 | 5 of 5 | 11.04 | 11.22 | 13.45 | 13.29 (2.88) | 0.82 / 0.82 |
| quiet | 120 min | 10.75 | 10.68 | 4 of 5 | 12.19 | 13.28 | 14.48 | 14.39 (2.87) | 0.84 / 0.84 |
| quiet | 180 min | 11.95 | 11.95 | equal in 5 of 5 | 13.38 | 16.10 | 15.69 | 15.69 (2.68) | 0.85 / 0.85 |

- MAE goes down at every horizon from 30 to 120 minutes, in every window, and is identical at 180.
- It goes down in all 5 folds at 30, 60 and 90 minutes, and in 4 of 5 at 120. Fold 1, which holds the two people
  whose rises do not track carbs, is 0.1 mg/dL worse at 120.
- Band coverage is unchanged.
- Gummi still beats CGM-only and last value at every horizon and in every window. The closest case is quiet windows
  at 30 minutes: Gummi 6.35, last value 6.77, CGM-only 6.83.

## Before and after: what the app shows at meal time

Each of 602 held-out meals is predicted at logging time with readings up to one hour before, then graded over the
next 2 hours.

| Meals | Peak bias before | Peak bias after | Peak error before | Peak error after | Curve error before | Curve error after | CGM-only peak / curve error | Last value peak / curve error |
|---|---|---|---|---|---|---|---|---|
| All 602 | -14.4 | -10.7 | 22.7 | 20.4 | 18.3 | 18.0 | 28.9 / 19.3 | 35.1 / 23.2 |
| 282 with 40 g+ carbs | -16.1 | -12.5 | 28.0 | 25.0 | 22.4 | 21.5 | 37.9 / 23.1 | 44.4 / 27.5 |
| 59 standardized breakfasts | -40.3 | -31.4 | 42.5 | 35.1 | 26.9 | 24.5 | 53.5 / 30.9 | 56.5 / 32.2 |

The walk nudge:
- 292 of the 602 meals really peaked at 140 or more.
- The forecast now reaches 140 for 135 of them, against 93 before, 45% more.
- False alarms (forecast at 140 or more, real peak below) go from 27 to 41 meals. Precision stays at 77%.
- For the standardized breakfast, the forecast reaches 140 in 27 of 52 high breakfasts, against 7.

One honest cost: the share of meals where Gummi's curve beats last value dips slightly, from 66.8% to 65.4%,
while the mean curve error improves.

## The demo day (p_012, day 6, through the fold model that never saw 012)

- Breakfast: "I predicted 153 for the standard breakfast. It was 174." Before, Gummi predicted 143. The forecast now
  crosses 140, so the walk nudge can fire.
- 19:24 candy: "I predicted 164. It was 161." Before, 145.
- Gummi beats CGM-only on 4 of 9 meals, as before. This person rises less than average after small midday meals,
  so CGM-only stays closer on those.

## Personal layer, retuned (D-71)

With the big-meal term in, the old personal layer (pseudo-counts 2 and 3) cut peak error only from 20.4 to 20.4 and
made curve error worse (18.0 to 18.2). Shrinking harder toward the population model (pseudo-counts 8 for the carb
factor and 9 for the offset) makes it a small net gain:

| Meals | Without the personal layer: peak / bias / curve | With it: peak / bias / curve |
|---|---|---|
| All 602 | 20.4 / -10.7 / 17.96 | 19.9 / -8.8 / 18.01 |
| 524 after 5 or more earlier meals | 20.6 / -10.8 / 18.22 | 19.9 / -8.6 / 18.25 |
| 59 standardized breakfasts | 35.1 / -31.4 / 24.5 | 33.3 / -30.6 / 23.5 |

## Limits

- 15 people. The gain is real in every fold at 30 to 90 minutes, but small next to the person-to-person spread.
- Gummi still under-predicts big spikes, by 11 mg/dL on average and 31 after the standardized breakfast.
- The 40 g threshold and the 150-to-180 ramp were chosen on these folds. Nested CV shows the ramp choice barely
  matters, but the threshold was compared on the same folds that report the result.
