# Walk effect: source, conversion, limits (decision D-11)

DRAFT, Data Lead. The effect size and the citation are checked against the paper. How Gummi turns them into
mg/dL is Gummi's own modeling choice and is labeled as such. Judge-facing wording needs the human's approval.

## What the app shows

- `simulate` adds the alternative "Walk 10 minutes after" with a lower peak and `effect_source`.
- A finished walk becomes a WalkSummary with `forecast_peak_drop_mg_dl` and `effect_source`.
- The label is always "literature" until a person's own meals pass the permutation test, then "your data".

## Source (literature)

Buffey AJ, Herring MP, Langley CK, Donnelly AE, Carson BP. The Acute Effects of Interrupting Prolonged Sitting Time in
Adults with Standing and Light-Intensity Walking on Biomarkers of Cardiometabolic Health in Adults: A Systematic
Review and Meta-analysis. Sports Medicine. 2022;52(8):1765-1787. doi:10.1007/s40279-022-01649-4

From the abstract: light-intensity walking breaks reduced postprandial glucose compared with uninterrupted sitting,
standardized mean difference -0.72 (95% CI -1.03 to -0.41). Standing breaks: -0.31 (95% CI -0.60 to -0.03).

## Conversion to mg/dL (Gummi's choice)

- drop = 0.72 x SD of post-meal rises in BIG IDEAs x min(walk minutes / 10, 1)
- SD of post-meal rises: 28.1 mg/dL (324 clean meals, at least 15 g carbs, no other meal within 150 minutes,
  15 participants), so a walk of 10 minutes or more gives at most 20.3 mg/dL. Shorter walks scale down linearly;
  longer walks are not extrapolated.
- Cap (ASSUMED): the drop never exceeds 50 percent of the meal's own predicted effect (peak with the meal minus the
  peak without it). Without the cap, 20 mg/dL would erase a small snack's whole effect, which no study supports.
- Only walks that start after the meal count, applied from the walk start onward.
- Sedentary (no steps) gives 0.

## Limits to say out loud

1. The meta-analysis pools lab studies of repeated short walking breaks during prolonged sitting, not one
   10-minute walk after a meal, and not this cohort.
2. A standardized mean difference turns into mg/dL only through an SD. Gummi uses the SD of rises in BIG IDEAs,
   which is a choice, not a measurement of the walk effect.
3. BIG IDEAs has no walk labels, so the cohort cannot validate the number. The wrist HR ablation added nothing to
   glucose forecasts, as in the prior work.

## Personal test ("your data")

`gummi_model.walk.permutation_test(rises_with_walk, rises_without_walk)`: one-sided permutation test (5,000
permutations, alpha 0.05) on one person's post-meal rises, meals with a walk after versus without. Fewer than 3
meals in either group returns "not enough data yet". "significant" switches the label to "your data" with the
person's own mean difference as the drop. With about 10 days of data, expect "not enough data yet" for most people,
and show that message as is.

## Step cadence to intensity (gummi_activity)

Tudor-Locke C, et al. Walking cadence (steps/min) and intensity in 21-40 year olds: CADENCE-adults. International
Journal of Behavioral Nutrition and Physical Activity. 2019;16:8. doi:10.1186/s12966-019-0769-6.
100 steps/min is about 3 METs (moderate), 130 steps/min about 6 METs (vigorous). Gummi: 1 to 99 "light" (ASSUMED,
below the published moderate threshold), 100 to 129 "moderate", 130 and up "vigorous". The bands come from adults
aged 21 to 40; Gummi's users are older (IMU50 could check the bands on wrist data if D-19 requires it).

Decision asked of the human (D-11): keep "literature" as the default label with this citation, the 10-minute
reference, and the 50 percent cap.
