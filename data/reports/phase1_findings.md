# Phase 1 findings: BIG IDEAs v1.1.3

DRAFT, Data Lead. Not judge-facing until the human approves the numbers (hard stop). Every number here comes from
`py data\scripts\run_local_pipeline.py` on the real files (the same code the Databricks job runs). The run gives
identical results on pandas 1.5.3, 2.2.3 and 3.0.5 (Databricks serverless environments 3 through 6).

## 1. Files and formats (T-4)

Downloaded with `data/scripts/download_bigideas.py` (route B): Dexcom, Food_Log and HR for all 16 folders, plus
Demographics.csv, LICENSE.txt and SHA256SUMS.txt. 51 files (16 Dexcom, 16 food logs, 16 HR, Demographics, LICENSE, SHA256SUMS), 240 MB, every checksum verified. File names carry the ID:
`001/Dexcom_001.csv`, `001/Food_Log_001.csv`, `001/HR_001.csv`.

Dexcom (Clarity export). Header row and first 3 lines of `Dexcom_001.csv`:
```
Index,Timestamp (YYYY-MM-DDThh:mm:ss),Event Type,Event Subtype,Patient Info,Device Info,Source Device ID,Glucose Value (mg/dL),Insulin Value (u),Carb Value (grams),Duration (hh:mm:ss),Glucose Rate of Change (mg/dL/min),Transmitter Time (Long Integer)
1,,FirstName,,2019,,,,,,,,
2,,LastName,,001,,,,,,,,
3,,PatientIdentifier,,2019-001,,,,,,,,
```
Rows 1 to 12 are patient-info and alert-setting rows. Glucose rows have Event Type EGV, for example
`13,2020-02-13 17:23:32,EGV,,,,iPhone G6,61.0,,,,,11101.0`. Bronze keeps all 37,080 rows. Silver keeps the
36,898 EGV rows. No reading in this cohort is the text "Low" or "High" (the loader maps them to 40 and 400 with a
flag if they appear).

Food log. Header row and first 3 lines of `Food_Log_001.csv`:
```
date,time,time_begin,time_end,logged_food,amount,unit,searched_food,calorie,total_carb,dietary_fiber,sugar,protein,total_fat
2020-02-13,18:00:00,2020-02-13 18:00:00,,Berry Smoothie,20.0,fluid ounce,Strawberry Smoothie,456.0,85.0,1.7,83.0,16.0,3.3
2020-02-13,20:30:00,2020-02-13 20:30:00,,Chicken Leg,1.0,,chicken leg,475.0,0.0,0.0,0.0,62.0,23.0
2020-02-13,20:30:00,2020-02-13 20:30:00,,Asparagus,4.0,,Asparagus,13.0,2.5,1.2,0.8,1.4,0.1
```
Three layouts in v1.1.3, all handled by `bigideas/loaders.py`:

| Layout | Participants | Details |
|---|---|---|
| Header, `date,time`, ISO dates | 001, 002, 004, 005, 006, 008 to 012, 014 | as above |
| Header, `date,time_of_day`, US dates | 007, 013, 015, 016 | `03/14/2020,13:44,...` (DATA_NOTES: both names exist) |
| No header, 11 columns | 003 | no time_end, dietary_fiber, total_fat; mapping proven by matching an identical Frosted Flakes entry (220 kcal, 52 g carbs, 20 g sugar, 2 g protein) |

`time_begin` is `YYYY-MM-DD HH:MM:SS` in every file and is the eating time. 1,422 food rows (1,364 with a header,
58 from 003).

HR (only for the ablation): the E4 files start with a byte-order mark, the value column is ` hr`, and HR_001 uses
minute-resolution US times (`2/13/20 15:29`) while the others use `2020-02-27 13:34:12`.

Demographics.csv: `ID,Gender,HbA1c`, IDs unpadded.

## 2. Cohort: correction to DATA_NOTES

Demographics.csv lists 9 FEMALE and 7 MALE participants (male: 002, 009, 011, 012, 013, 014, 016). HbA1c 5.3 to 6.4
percent. DATA_NOTES section 1 says "16 post-menopausal women" and judge answer 5 in PROJECT_OVERVIEW says "Trained on
16 women". The file says otherwise, so the pitch line needs to change (sent as an FYI; DATA_NOTES is not the Data
Lead's file to edit).

Mean glucose per participant: 93 to 130 mg/dL, readings from 40 to 261 mg/dL. A flat, high-normal to prediabetic
cohort, as expected.

## 3. Coverage and the exclusion candidate (D-20)

| Participant | Days | Readings | Completeness | Biggest gap (min) | Islands |
|---|---|---|---|---|---|
| 001 | 10 | 2561 | 0.985 | 190 | 2 |
| 002 | 9 | 2119 | 0.927 | 845 | 2 |
| 003 | 9 | 2302 | 0.995 | 65 | 2 |
| 004 | 9 | 2164 | 0.959 | 460 | 2 |
| 005 | 10 | 2558 | 0.994 | 76 | 2 |
| 006 | 11 | 2847 | 1.000 | 5 | 1 |
| 007 | 9 | 2207 | 0.965 | 400 | 2 |
| 008 | 10 | 2505 | 0.977 | 105 | 5 |
| 009 | 9 | 2306 | 1.000 | 10 | 1 |
| 010 | 9 | 2148 | 0.942 | 400 | 3 |
| 011 | 11 | 2843 | 0.995 | 45 | 3 |
| 012 | 9 | 2169 | 0.984 | 120 | 3 |
| 013 | 8 | 1979 | 1.000 | 5 | 1 |
| 014 | 9 | 2240 | 1.000 | 5 | 1 |
| **015** | 9 | 1673 | **0.753** | **1315** | 4 |
| 016 | 9 | 2277 | 0.990 | 100 | 3 |

015 matches the published exclusion exactly: 75 percent completeness and a 1,315-minute (21.9-hour) gap. The
baseline reproduces only with 015 excluded (section 5).

A second problem, new here: 015's food log does not line up with its CGM. The log runs 2020-07-05 to 07-13, the CGM
2020-07-19 to 07-27, so none of 015's 45 meals has glucose around it (every other participant's log overlaps their
CGM). Shifting the log by 14 days, or by any 6-hour step up to 20 days, does not bring back clear post-meal rises
(best Spearman carbs-to-rise 0.28 at 17 days, against 0.52 for participant 014 at zero shift), so the log cannot be
re-aligned with confidence.

Recommendation for D-20: exclude 015 from training and evaluation. Keep 015's CGM in the replay tables (flagged
`excluded_from_training`) so the fleet still streams 16 people, and every prediction for 015 is truly out of sample.
015's replay meals fall before its first CGM reading (negative day_index), so a producer starting at day 1 or later
never releases them. Needs a human yes (hard stop).

## 4. Meals

- Food rows within 15 minutes of each other form one meal: 688 meals (643 for the 15 included participants),
  24 to 76 per person. Median meal 35 g carbs (quartiles 13 and 58.5 g). Self-reported logs are noisy: the largest
  logged meal has 463 g carbs.
- Standardized breakfast found for all 16 participants, 3 to 5 each, 64 in total. Logged as "Standard Breakfast",
  "Std breakfast", "Std bfast", or by the cereal itself ("Frosted Flake(s)", "Corn Flakes" with searched_food
  "(Kellogg's) Frosted Flakes"). 001 and 002 logged 35 g carbs (0.75 cup plus milk), the others 56.5 g.
- Post-meal rise (peak within 150 minutes minus the median of the 30 minutes before eating): meals with CGM
  coverage 615; meals followed by another meal within the window 230; clean meals with at least 15 g carbs and no
  overlap 324. Median rise 36.5 mg/dL, SD 28.1 mg/dL.
- Rise versus carbs: Spearman 0.45 pooled. Per person from -0.29 (016) to 0.67 (006). Two people (002, 016) show no
  positive relation, so a carb count alone does not predict their rise.
- Same breakfast, very different people: the mean rise after the standardized breakfast runs from 29.8 mg/dL (003)
  to 95.5 mg/dL (010), more than three-fold for the same food. Median 1.04 mg/dL per gram of carbs. This is the case
  for Gummi's personal layer (carb factor and offset learned from each person's grades).

## 5. Published baseline reproduced (Phase 1 target)

Protocol from Seyedebrahimi et al. 2026 and their PhysioFusion code: CGM as the master clock, islands split at gaps
over 15 minutes, 24 readings of history, target 30 minutes ahead, five-fold participant-grouped CV (GroupKFold),
StandardScaler plus LinearRegression. `tests/test_baseline_no_leakage.py` fails if any participant is in train and test.

| 30 minutes ahead, RMSE mg/dL | Ours, 15 (015 excluded) | Published | Ours, all 16 |
|---|---|---|---|
| CGM-only linear regression | 13.90 +/- 0.58 | 13.90 +/- 0.58 | 13.81 +/- 0.70 |
| Persistence (last value) | 16.49 | 16.49 | 16.36 |
| Mean | 23.37 | 22.76 | 23.15 |

Linear regression and persistence match to the second decimal on 34,268 windows. The mean baseline differs by 0.6,
likely a different choice of which mean; it is the weakest baseline and is reported as computed.

## 6. Heart-rate ablation (approved download)

Per-minute heart rate (30 to 220 bpm) added to Gummi's features, same folds, 27,583 origins that have HR. RMSE changes
by +0.01 to +0.05 mg/dL at every horizon (0 to 4 of 5 folds better, no consistent gain). Same as the prior work: wrist
signals add nothing. HR stays out of gummi_model, as the kit's scope already says.

## 7. Small experiments not adopted

- Morning carbs as a separate feature (`GUMMI_MORNING_FEATURE=1`): better standardized-breakfast peaks, no gain
  overall, slightly worse meal-window RMSE. Off.
- Walk effect: see `walk_effect.md`.

Next: `model_eval.md` (gummi_model v1 against the baselines, meal ablation, band coverage, meal-time predictions).
