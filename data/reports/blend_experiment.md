# Blend of Gummi and CGM-only: tried, not shipped (D-73)

DRAFT, Data Lead, 2026-10-03. Asked for by Backend (REQUEST 2310, item 2).

## Result

A per-horizon blend, y = w × Gummi + (1 − w) × CGM-only, lowers mean MAE by only 0.02 mg/dL overall and 0.05 to
0.06 in meal windows. It helps in just 2 or 3 of the 5 folds, does nothing in quiet windows, and would undo most of
the big-spike fix (D-70). Not shipped. The shipped model stays gummi_model_v1_2.

## Method

- Same 5 participant-grouped folds, nested. For each outer fold, w was chosen on an inner 4-fold participant-grouped
  CV over that fold's training people only. It is the value on a 0 to 1 grid (steps of 0.05) with the lowest MAE,
  picked separately for every 5-minute step and for meal and quiet windows (a meal known at forecast time).
- The blend's bands come from the same inner out-of-fold residuals.
- Each outer fold then scored Gummi alone, the blend, and CGM-only on people never used to choose w.
- Code: data/scripts/blend_experiment.py. Outputs: data/local_out/blend_experiment/.

## Numbers (MAE, mg/dL, mean of 5 folds)

| Window | Minutes ahead | Gummi | Blend | Change | Folds where the blend is better | Coverage, Gummi / blend |
|---|---|---|---|---|---|---|
| all | 30 | 8.902 | 8.883 | −0.019 | 2 of 5 | 0.799 / 0.798 |
| all | 60 | 12.059 | 12.036 | −0.023 | 3 of 5 | 0.800 / 0.799 |
| all | 90 | 13.147 | 13.125 | −0.022 | 2 of 5 | 0.800 / 0.799 |
| all | 120 | 14.237 | 14.213 | −0.024 | 2 of 5 | 0.797 / 0.797 |
| all | 180 | 15.155 | 15.149 | −0.006 | 3 of 5 | 0.799 / 0.797 |
| meal | 60 | 15.724 | 15.660 | −0.064 | 3 of 5 | 0.798 / 0.796 |
| meal | 120 | 17.885 | 17.823 | −0.062 | 2 of 5 | 0.759 / 0.756 |
| quiet | 60 | 8.472 | 8.471 | −0.001 | 1 of 5 | 0.805 / 0.805 |
| quiet | 120 | 10.682 | 10.683 | +0.001 | 0 of 5 | 0.836 / 0.837 |

Chosen weights:
- Quiet windows: 1.0 (Gummi alone) almost everywhere, 0.9 to 0.95 at 180 min.
- Meal windows: 0.7 to 0.85.

## Why not ship

1. **The rule fails.** "Better or equal at every horizon in both windows, coverage holds" does not hold. Quiet windows
   at 120 min get 0.001 worse, and meal-window coverage drops by about 0.003. Both are within noise, and so is the gain.
2. **The gain is not consistent.** It shows in 2 or 3 of 5 folds: half the people see it, half don't.
3. **It undoes the spike fix.** In meal windows the blend pulls about 20% of the forecast toward CGM-only, which
   predicts peaks 25 mg/dL too low. Since the peak of a blend is at most the blend of the peaks, on the 602 held-out
   meals the blend's peak bias is at best −13.6 mg/dL, against −10.7 for Gummi. The forecast would catch at most 96 of
   the 292 meals that really reach 140, against 135 for Gummi. That costs the walk nudge.

## Optional boosting check

Not run. Pranav expected trees on 15 people and about 600 meals to overfit people. The blend, a far simpler correction than trees,
already shows no reliable gain, so I would expect the same negative result.

## Live note

Backend's live nowcast grades for p_012 (Gummi 12.6, CGM-only 11.3, last value 14.3) come from 5 grades. In CV,
quiet windows (most nowcasts) favor Gummi over CGM-only by 0.5 to 1.5 mg/dL at 30 to 180 minutes ahead, less at the
shortest steps. Five grades for one person going the other way is within day-to-day noise; the blend found nothing
to add there (its quiet weight is 1.0).
