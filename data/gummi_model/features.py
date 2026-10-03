"""Feature construction shared by training (vectorized over origins) and inference (one origin).

Origin t0 = data_through, the newest confirmed reading. Horizon k targets t0 + 5k minutes.
Every model predicts the change from the newest reading: y_k = glucose(t0 + 5k) - glucose(t0).
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from . import kernels
from .config import HISTORY, KERNEL_PEAK_MIN, MEAL_COLS, MORNING_END_HOUR, STEP_MIN

BASE_NAMES = (
    ["last"]
    + [f"hist_{i:02d}_minus_last" for i in range(HISTORY)]
    + ["slope15", "slope30", "curvature", "tod_sin", "tod_cos", "mean24_minus_last"]
)
HR_NAMES = ["hr_mean15", "hr_delta15"]


def meal_names(cols=MEAL_COLS) -> list[str]:
    return [f"{c}_{kind}" for c in cols for kind in ("absorbed", "rate")] + ["min_since_meal"]


MEAL_NAMES = meal_names()


def add_derived(meals: pd.DataFrame, local_hour: np.ndarray | None = None) -> pd.DataFrame:
    """Add derived meal columns. local_hour: hour of each meal in the person's local time
    (training data is already local; inference converts UTC with the profile timezone)."""
    meals = meals.copy()
    if local_hour is None:
        ts = pd.to_datetime(meals["eaten_at"])
        local_hour = (ts.dt.hour + ts.dt.minute / 60.0).to_numpy()
    carbs = pd.to_numeric(meals["carbs_g"], errors="coerce").fillna(0.0).to_numpy() if "carbs_g" in meals else 0.0
    meals["carbs_morning_g"] = np.where(np.asarray(local_hour) < MORNING_END_HOUR, carbs, 0.0)
    return meals


def base_features(hist: np.ndarray, hour_frac: np.ndarray, mean24: np.ndarray) -> np.ndarray:
    """hist: (n, HISTORY) oldest -> newest. hour_frac: (n,) local hour 0-24. mean24: (n,).

    Returns (n, len(BASE_NAMES)).
    """
    hist = np.atleast_2d(np.asarray(hist, dtype=float))
    last = hist[:, -1]
    rel = hist - last[:, None]
    slope15 = (hist[:, -1] - hist[:, -4]) / 15.0
    slope30 = (hist[:, -1] - hist[:, -7]) / 30.0
    curv = (hist[:, -1] - 2.0 * hist[:, -4] + hist[:, -7]) / 225.0
    ang = 2.0 * np.pi * np.asarray(hour_frac, dtype=float) / 24.0
    mean_rel = np.asarray(mean24, dtype=float) - last
    return np.column_stack([last, rel, slope15, slope30, curv, np.sin(ang), np.cos(ang), mean_rel])


def meal_features(age_t0: np.ndarray, amounts: np.ndarray, horizons: np.ndarray, cols=MEAL_COLS) -> np.ndarray:
    """Meal features for every (origin, horizon).

    age_t0: (n, M) minutes from each known meal to t0 (negative = eaten after t0); NaN = not known.
    amounts: (n, M, len(cols)) grams (NaN treated as 0).
    horizons: (H,) steps.
    Returns (n, H, 2 * len(cols) + 1): per column the grams absorbed between t0 and t0+5k and the
    grams-weighted absorption rate at t0+5k, plus minutes since the latest eaten meal (cap 360).
    """
    age_t0 = np.atleast_2d(np.asarray(age_t0, dtype=float))
    n, M = age_t0.shape
    H = len(horizons)
    out = np.zeros((n, H, 2 * len(cols) + 1))
    if M == 0:
        out[:, :, -1] = 360.0
        return out
    known = ~np.isnan(age_t0)
    a0 = np.where(known, age_t0, -1e9)[:, None, :]                            # (n, 1, M)
    aT = a0 + (np.asarray(horizons, dtype=float) * STEP_MIN)[None, :, None]   # (n, H, M)
    amt = np.nan_to_num(np.asarray(amounts, dtype=float))                     # (n, M, C)
    amt = np.where(known[:, :, None], amt, 0.0)
    cache = {}
    for j, col in enumerate(cols):
        peak = KERNEL_PEAK_MIN[col]
        if peak not in cache:
            absorbed = kernels.cdf(aT, peak) - kernels.cdf(np.broadcast_to(a0, aT.shape), peak)
            cache[peak] = (absorbed, kernels.rate(aT, peak))
        absorbed, rate = cache[peak]
        out[:, :, 2 * j] = np.einsum("nhm,nm->nh", absorbed, amt[:, :, j])
        out[:, :, 2 * j + 1] = np.einsum("nhm,nm->nh", rate, amt[:, :, j])
    eaten = np.where(aT >= 0, aT, np.inf)
    out[:, :, -1] = np.minimum(eaten.min(axis=2), 360.0)
    return out


def design(base: np.ndarray, meal: np.ndarray | None, hr: np.ndarray | None, k_index: int) -> np.ndarray:
    """Stack the feature blocks for one horizon index into a 2-D design matrix."""
    blocks = [base]
    if meal is not None:
        blocks.append(meal[:, k_index, :])
    if hr is not None:
        blocks.append(hr)
    return np.column_stack(blocks)


def feature_names(feature_set: str, cols=MEAL_COLS) -> list[str]:
    names = list(BASE_NAMES)
    if feature_set in ("cgm_meals", "cgm_meals_hr"):
        names += meal_names(cols)
    if feature_set == "cgm_meals_hr":
        names += HR_NAMES
    return names
