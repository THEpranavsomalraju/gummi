"""Personal layer: a personal carb factor and offset fitted on the person's own logged meals.

No Kalman filter (cut in team review). Both numbers shrink toward the population model (factor 1, offset 0) when
evidence is thin. ew_offset (an exponentially weighted mean of grade errors) stays available but is not used:
grades already include the applied offset.
"""
from __future__ import annotations

from datetime import datetime, timezone

import numpy as np
import pandas as pd

from . import config as C


def ew_offset(grades: list[dict]) -> tuple[float, int]:
    """Signed offset (actual - predicted) from graded predictions, newest weighted most."""
    rows = [g for g in grades or [] if g.get("status", "graded") == "graded" and g.get("gummi_bias_mg_dl") is not None]
    if not rows:
        return 0.0, 0
    rows = sorted(rows, key=lambda g: str(g.get("graded_at", "")))
    b = np.array([float(g["gummi_bias_mg_dl"]) for g in rows])
    w = (1 - C.OFFSET_ALPHA) ** np.arange(len(b))[::-1]
    est = float((w * b).sum() / w.sum())
    shrunk = est * len(b) / (len(b) + C.OFFSET_SHRINK_N)
    return float(np.clip(shrunk, -C.OFFSET_CAP, C.OFFSET_CAP)), len(b)


def meal_terms(model, ctx, eaten) -> tuple[np.ndarray, np.ndarray] | None:
    """Evidence from one logged meal whose 2-hour window is covered by confirmed readings.

    Origin = the last reading before eating. c = the model's meal contribution at each 5-minute step of the window,
    r = actual minus the model's no-meal prediction at the same steps. None when the window is not covered.
    """
    from .model import UserContext   # local import avoids a cycle
    cgm = ctx.cgm_df.copy()
    cgm["t"] = pd.to_datetime(cgm["t"], utc=True).astype("datetime64[ns, UTC]")
    eaten = pd.Timestamp(eaten)
    eaten = eaten.tz_localize("UTC") if eaten.tzinfo is None else eaten.tz_convert("UTC")
    before = cgm[cgm["t"] <= eaten]
    after = cgm[(cgm["t"] > eaten) & (cgm["t"] <= eaten + pd.Timedelta(minutes=120))]
    if len(before) < C.HISTORY or len(after) < 18:
        return None
    meals = ctx.meals_df[pd.to_datetime(ctx.meals_df["eaten_at"], utc=True) <= eaten + pd.Timedelta(minutes=1)]
    sub = UserContext(ctx.user_id, ctx.profile, before, meals, None, None)
    _, _, tgt, val, _, _, contrib = model._predict(sub, eaten + pd.Timedelta(minutes=1), np.arange(1, 25),
                                                   apply_personal=False)
    times = pd.to_datetime(tgt * 60.0, unit="s", utc=True).astype("datetime64[ns, UTC]")
    actual = pd.merge_asof(pd.DataFrame({"t": times}), after[["t", "glucose_mg_dl"]], on="t", direction="nearest",
                           tolerance=pd.Timedelta(minutes=C.MATCH_TOL_MIN))["glucose_mg_dl"].to_numpy()
    ok = ~np.isnan(actual)
    if ok.sum() < 12 or np.abs(contrib[ok]).sum() < 1e-6:
        return None
    return contrib[ok], actual[ok] - (val - contrib)[ok]


def fit_personal(terms: list[tuple[np.ndarray, np.ndarray]], with_offset: bool = False) -> tuple[float, float]:
    """Carb factor (and optionally a constant offset) from meal_terms, shrunk toward (1, 0) and clipped.

    Without offset: factor = sum(c*r) / sum(c^2). With offset: least squares of r on c and a constant.
    Shrinkage uses pseudo-counts in meals (CARB_FACTOR_SHRINK, OFFSET_SHRINK_N).
    """
    n = len(terms)
    if n == 0:
        return 1.0, 0.0
    c = np.concatenate([t[0] for t in terms])
    r = np.concatenate([t[1] for t in terms])
    if with_offset:
        A = np.array([[float((c * c).sum()), float(c.sum())], [float(c.sum()), float(len(c))]])
        b = np.array([float((c * r).sum()), float(r.sum())])
        try:
            f_raw, o_raw = np.linalg.solve(A, b)
        except np.linalg.LinAlgError:
            f_raw, o_raw = 1.0, 0.0
    else:
        den = float((c * c).sum())
        f_raw, o_raw = (float((c * r).sum()) / den if den > 0 else 1.0), 0.0
    f = (f_raw * n + 1.0 * C.CARB_FACTOR_SHRINK) / (n + C.CARB_FACTOR_SHRINK)
    o = o_raw * n / (n + C.OFFSET_SHRINK_N)
    lo, hi = C.CARB_FACTOR_BOUNDS
    return float(np.clip(f, lo, hi)), float(np.clip(o, -C.OFFSET_CAP, C.OFFSET_CAP))


def carb_factor(model, ctx) -> tuple[float, int]:
    """Least-squares scale between the model's meal contribution and what actually happened, over the person's
    logged meals with covered windows: factor = sum(c * r) / sum(c^2), shrunk toward 1 and clipped."""
    if ctx.meals_df is None or len(ctx.meals_df) == 0 or model.feature_set == "cgm":
        return 1.0, 0
    terms = [t for t in (meal_terms(model, ctx, e) for e in ctx.meals_df["eaten_at"]) if t is not None]
    if not terms:
        return 1.0, 0
    return fit_personal(terms)[0], len(terms)


def update_personal(model, ctx, grades: list[dict]) -> dict:
    """Personal carb factor and offset, fit together on the person's logged meals whose windows have closed.

    Evaluated online in gummi_ml.personal_layer_eval (factor plus offset): peak error 22.9 -> 21.2 mg/dL once a
    person has 5 or more closed meals, better in all 5 folds. The offset comes from the meals' raw residuals, not
    from grades, so it does not chase its own corrections. Grades are only counted.
    """
    terms = []
    if ctx.meals_df is not None and len(ctx.meals_df) and model.feature_set != "cgm":
        terms = [t for t in (meal_terms(model, ctx, e) for e in ctx.meals_df["eaten_at"]) if t is not None]
    factor, offset = fit_personal(terms, with_offset=True)
    n_grades = len([g for g in grades or [] if g.get("status", "graded") == "graded"])
    prev = dict(ctx.personal or {})
    prev.update({
        "offset_mg_dl": round(offset, 1),
        "carb_factor": round(factor, 2),
        "n_grades": n_grades,
        "n_meals_used": len(terms),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    })
    return prev
