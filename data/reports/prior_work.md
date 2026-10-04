# Prior work: PhysioFusion (Seyedebrahimi, Ojeda, Zarrintaj 2026)

Paper: "A Leakage-Controlled Evaluation of Multimodal Sensor Fusion for Wrist-Worn Glucose Estimation", medRxiv, posted 2026-08-04, doi 10.64898/2026.08.03.26359550 (verified via Sciety).
Code: https://github.com/mirmehdi/PhysioFusion (read 2026-10-03, default branch).

## Exact protocol to reproduce (from the code, not the abstract)

| Item | What PhysioFusion does | Source |
|---|---|---|
| Dataset version | BIG IDEAs **v1.1.2** (we use v1.1.3; v1.1.3 changed food-log dates, not the CGM, per the PhysioNet page) | every track script `BIG = ...-1.1.2` |
| Excluded subject | **015**: completeness 0.753, biggest gap 1315 min (~22 h). 15 subjects used. | `_archive/build_check.py`, `cgm_cohort_summary.csv` |
| Dexcom parsing | `pd.read_csv(Dexcom_XXX.csv)`, keep `Event Type == "EGV"`, time = `Timestamp (YYYY-MM-DDThh:mm:ss)`, value = `Glucose Value (mg/dL)` coerced to numeric. The first ~12 rows are patient metadata. | `windowing.load_subject_cgm` |
| File names | `<SIGNAL>_<ID>.csv`, e.g. `Dexcom_001.csv`, `HR_001.csv`, `ACC_001.csv` (also confirmed on the PhysioNet 001 listing) | `features.load_e4_signal` |
| E4 file format | Columns have leading spaces, so strip them. The time column is `datetime`; value columns such as `hr`, `eda`, `temp`, `acc_x/acc_y/acc_z`. | `features.load_e4_signal` |
| Gap segmentation | Sort by time; a new "island" starts when the gap to the previous reading is **> 15 min** | `windowing.segment_by_gaps` |
| Windows | Within each island only: history = **24 readings** (2 h), step = 1, target = the reading **6 steps after the last history reading** (30 min), i.e. `y = g[start+history+horizon-1]` with horizon=6 | `windowing.make_windows` |
| Wrist features | Per CGM timestamp t, summarize samples in **(t−5 min, t]**: mean/std/min/max. NaN when coverage < 50 samples (ACC < 1000). HR clipped to 30–200. ACC magnitude = √(x²+y²+z²). | `features.summarize_to_cgm`, `build_subject_table` |
| Split | `GroupKFold(n_splits=5)` on subject id, all 5 folds, mean ± std across folds | `splits.subject_grouped_split`, `model_compare.py` |
| Models | `StandardScaler + LinearRegression` (winner), Ridge(1.0), Lasso(0.1), ElasticNet, RandomForest(100), GradientBoosting. Persistence = last history value. Mean = training-set mean of y. | `model_compare.py`, `baseline_check.py` |
| HRV | E4 detects only ~33% of beats; Kubios correction via NeuroKit2; judged unfit at 5-min resolution | `features.summarize_hrv_clean_to_cgm` |

Cohort summary from their repo (CGM only, v1.1.2):

| subject | days | readings | mean | std | max gap (min) | completeness |
|---|---|---|---|---|---|---|
| 001 | 9 | 2561 | 106 | 16 | 190 | 0.986 |
| 002 | 7 | 2119 | 130 | 21 | 845 | 0.927 |
| 003 | 8 | 2302 | 108 | 18 | 65 | 0.995 |
| 004 | 7 | 2164 | 113 | 18 | 460 | 0.959 |
| 005 | 8 | 2558 | 105 | 15 | 76 | 0.995 |
| 006 | 9 | 2847 | 125 | 29 | 5 | 1.000 |
| 007 | 7 | 2207 | 93 | 18 | 400 | 0.966 |
| 008 | 8 | 2505 | 111 | 18 | 105 | 0.977 |
| 009 | 8 | 2306 | 128 | 24 | 10 | 1.000 |
| 010 | 7 | 2148 | 112 | 29 | 400 | 0.943 |
| 011 | 9 | 2843 | 119 | 25 | 45 | 0.996 |
| 012 | 7 | 2169 | 122 | 20 | 120 | 0.984 |
| 013 | 6 | 1979 | 127 | 23 | 5 | 1.001 |
| 014 | 7 | 2240 | 116 | 21 | 5 | 1.000 |
| **015** | 7 | 1673 | 109 | 15 | **1315** | **0.753** |
| 016 | 7 | 2277 | 106 | 17 | 100 | 0.990 |

## Published numbers to match (30 min, 5-fold subject-grouped)

- Linear regression (CGM history only): **13.90 ± 0.58 mg/dL RMSE**
- Persistence: **16.49**
- Wrist-only: 22.58; time-of-day: 22.63; training mean: 22.76
- Adding wrist signals (summary or full sequences) gave no gain.

## What Gummi takes from this

1. Reuse the exact protocol for `04_baseline_repro.py`, so our number is comparable. Any deviation (e.g. a 16th subject) gets reported separately.
2. Recommendation for **D-20**: exclude 015 for the published comparison. Gummi's own model can still train on all 16, but it is reported both ways.
3. Food logs were **not** used by PhysioFusion, so "do logged meals help?" is genuinely new.
4. Note that `make_windows` predicts one point. Gummi's model is multi-horizon (5–240 min from `data_through`) with the same islands and history.
