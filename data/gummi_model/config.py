"""gummi_model constants. Values marked TUNE are starting points, tuned with participant-grouped CV."""
VERSION = "gummi_model_v1"

STEP_MIN = 5                  # CGM cadence (Dexcom G6)
HISTORY = 24                  # readings of history (2 h), same as the published baseline
EVAL_MAX_H = 36               # contract horizon: data_through + 180 min (60-min delay gap + 2-hour forecast)
MAX_H = 48                    # trained out to +240 min so a late Dexcom upload still gets a full forecast
DELAY_MIN = 60                # Dexcom US delay; training treats meals up to data_through + 60 as known
MEAN_LOOKBACK_MIN = 24 * 60   # personal level feature: mean of the previous 24 h of confirmed readings
MATCH_TOL_MIN = 2.5           # a reading counts for a 5-minute slot if within this many minutes

# Gamma absorption kernels, integer shape 3 so the CDF has a closed form (numpy only at inference).
# Peak times are TUNE values; carbs ~55 min matches typical mixed-meal CGM peaks in this cohort's range.
KERNEL_SHAPE = 3
KERNEL_PEAK_MIN = {
    "carbs_g": 55.0,
    "sugar_g": 35.0,
    "fiber_g": 90.0,
    "protein_g": 120.0,
    "fat_g": 150.0,
    "carbs_morning_g": 55.0,      # derived: carbs of meals eaten before MORNING_END_HOUR local time
}
INPUT_MACROS = ["carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g"]   # what callers pass per meal
MORNING_END_HOUR = 11
import os as _os
# Experiment (13 participants, grouped CV): the morning-carbs feature cut standardized-breakfast peak error
# (40.6 -> 34.1 mg/dL) but left all-meal peak error unchanged (22.6) and raised meal-window RMSE slightly
# (60 min: 22.19 -> 22.78). Not adopted; the code path stays for a re-test. See reports/phase1_findings.md.
MORNING_FEATURE = _os.environ.get("GUMMI_MORNING_FEATURE", "0") == "1"
MEAL_COLS = INPUT_MACROS + (["carbs_morning_g"] if MORNING_FEATURE else [])
MEAL_LOOKBACK_MIN = 6 * 60    # older meals contribute ~nothing

RIDGE_ALPHA = 10.0            # TUNE
BAND_Q = (0.10, 0.90)         # 80% bands from held-out residual quantiles
MEAL_WINDOW_MIN = 180         # a target time within 0-180 min after a logged meal is a "meal window"

# Personal layer (no Kalman filter, per DECISIONS / PROJECT_OVERVIEW scope)
OFFSET_ALPHA = 0.3            # exponential weight of the newest grade's signed error
OFFSET_SHRINK_N = 3.0         # pseudo-count toward 0 offset
OFFSET_CAP = 25.0             # mg/dL
CARB_FACTOR_SHRINK = 2.0      # pseudo-count toward a factor of 1.0
CARB_FACTOR_BOUNDS = (0.5, 2.0)

# Gummi's estimate trend thresholds, mg/dL per minute (CONTRACT v0.2 values)
TREND_THRESHOLDS = {"rising_fast": 2.0, "rising": 0.5, "falling": -0.5, "falling_fast": -2.0}
CONFIDENCE_BAND = {"high": 25.0, "medium": 45.0}

# Walk effect (D-11): literature until a person's own data passes the permutation test.
WALK = {
    "effect_source": "literature",
    "effect_size_d": 0.72,
    "reference_minutes": 10,
    # ASSUMED (conservative): a walk never removes more than half of the meal's predicted rise.
    "max_fraction_of_meal_effect": 0.5,
    "citation": ("Buffey AJ, Herring MP, Langley CK, Donnelly AE, Carson BP (2022). The Acute Effects of "
                 "Interrupting Prolonged Sitting Time in Adults with Standing and Light-Intensity Walking on "
                 "Biomarkers of Cardiometabolic Health in Adults: A Systematic Review and Meta-analysis. "
                 "Sports Medicine 52:1765-1787. doi:10.1007/s40279-022-01649-4"),
}
PERMUTATION_MIN_PER_GROUP = 3
PERMUTATION_N = 5000
PERMUTATION_ALPHA = 0.05
