"""Training-time code: sample construction from silver tables, ridge per horizon, artifact export.

Runs on a laptop or a Databricks serverless notebook (numpy + pandas; scikit-learn only for GroupKFold
in evaluate.py). Inference (model.py) never imports this module.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from numpy.lib.stride_tricks import sliding_window_view

from . import config as C
from .features import add_derived, base_features, design, feature_names, meal_features


# ----------------------------------------------------------------------------------------------
# Samples
# ----------------------------------------------------------------------------------------------
@dataclass
class Samples:
    pid: np.ndarray            # (n,) participant id
    t0: np.ndarray             # (n,) datetime64 of data_through
    last: np.ndarray           # (n,) glucose at t0
    hist: np.ndarray           # (n, HISTORY) raw history, oldest -> newest
    base: np.ndarray           # (n, F_base)
    meal: np.ndarray           # (n, H, F_meal) float32
    hr: np.ndarray | None      # (n, 2) or None
    y: np.ndarray              # (n, H) change from last; NaN when no reading at the target time
    meal_window: np.ndarray    # (n, H) bool: target 0-180 min after ANY logged meal (truth, for reporting)
    meal_known: np.ndarray     # (n, H) bool: target 0-180 min after a meal known at "now" (for bands)
    horizons: np.ndarray = field(default_factory=lambda: np.arange(1, C.MAX_H + 1))

    def __len__(self) -> int:
        return len(self.pid)

    def subset(self, mask: np.ndarray) -> "Samples":
        return Samples(self.pid[mask], self.t0[mask], self.last[mask], self.hist[mask], self.base[mask],
                       self.meal[mask], None if self.hr is None else self.hr[mask], self.y[mask],
                       self.meal_window[mask], self.meal_known[mask], self.horizons)


def _minutes(ts) -> np.ndarray:
    return pd.to_datetime(pd.Series(ts)).to_numpy(dtype="datetime64[s]").astype(np.int64) / 60.0


def _hr_window_means(hr_min_t: np.ndarray, hr_vals: np.ndarray, t0: np.ndarray) -> np.ndarray:
    """mean HR over (t0-15, t0] and change vs (t0-30, t0-15]. NaN when fewer than 5 minutes present."""
    cs = np.concatenate([[0.0], np.cumsum(hr_vals)])
    def mean_between(a, b):
        lo = np.searchsorted(hr_min_t, a, side="right")
        hi = np.searchsorted(hr_min_t, b, side="right")
        cnt = hi - lo
        s = cs[hi] - cs[lo]
        return np.where(cnt >= 5, s / np.maximum(cnt, 1), np.nan)
    m15 = mean_between(t0 - 15, t0)
    m30 = mean_between(t0 - 30, t0 - 15)
    return np.column_stack([m15, m15 - m30])


def build_samples(silver_cgm: pd.DataFrame, silver_meals: pd.DataFrame,
                  hr_minutes: pd.DataFrame | None = None, participants: list[str] | None = None,
                  max_h: int = C.MAX_H) -> Samples:
    """One sample per origin (every reading with HISTORY readings before it in the same island).

    silver_cgm: participant_id, ts, glucose, island.  silver_meals: participant_id, eaten_at, MEAL_COLS.
    hr_minutes (optional): participant_id, minute, hr (per-minute mean heart rate).
    """
    horizons = np.arange(1, max_h + 1)
    parts = []
    for pid, g in silver_cgm.sort_values(["participant_id", "ts"]).groupby("participant_id", sort=True):
        if participants and pid not in participants:
            continue
        g = g.reset_index(drop=True)
        v = g["glucose"].to_numpy(dtype=float)
        t = _minutes(g["ts"])
        pos = g.groupby("island").cumcount().to_numpy()
        idx = np.where(pos >= C.HISTORY - 1)[0]
        if len(idx) == 0:
            continue
        hist = sliding_window_view(v, C.HISTORY)[idx - (C.HISTORY - 1)]
        ok = ~np.isnan(hist).any(axis=1)
        idx, hist = idx[ok], hist[ok]
        t0 = t[idx]
        ts0 = pd.to_datetime(g["ts"].to_numpy()[idx])
        hour = (ts0.hour + ts0.minute / 60.0).to_numpy(dtype=float)
        # causal 24 h mean of confirmed readings
        cs = np.concatenate([[0.0], np.cumsum(np.nan_to_num(v))])
        left = np.searchsorted(t, t0 - C.MEAN_LOOKBACK_MIN, side="right")
        mean24 = (cs[idx + 1] - cs[left]) / (idx + 1 - left)
        base = base_features(hist, hour, mean24)
        # targets matched by time, not by index
        T = t0[:, None] + C.STEP_MIN * horizons[None, :]
        j = np.clip(np.searchsorted(t, T), 1, len(t) - 1)
        prev_closer = np.abs(t[j - 1] - T) <= np.abs(t[j] - T)
        jj = np.where(prev_closer, j - 1, j)
        hit = np.abs(t[jj] - T) <= C.MATCH_TOL_MIN
        y = np.where(hit, v[jj] - v[idx][:, None], np.nan)
        # meals
        m = silver_meals[silver_meals["participant_id"] == pid].sort_values("eaten_at")
        if len(m):
            m = add_derived(m)   # training timestamps are already the participant's local time
        e = _minutes(m["eaten_at"]) if len(m) else np.zeros(0)
        A = m[C.MEAL_COLS].to_numpy(dtype=float) if len(m) else np.zeros((0, len(C.MEAL_COLS)))
        age = t0[:, None] - e[None, :]                                   # (n, M)
        known = (age >= -C.DELAY_MIN) & (age <= C.MEAL_LOOKBACK_MIN)
        age_known = np.where(known, age, np.nan)
        amounts = np.broadcast_to(A[None, :, :], (len(idx), len(e), len(C.MEAL_COLS)))
        meal = meal_features(age_known, amounts, horizons, C.MEAL_COLS).astype(np.float32)
        since = T[:, :, None] - e[None, None, :]                         # (n, H, M) minutes after each meal
        in_win = (since >= 0) & (since <= C.MEAL_WINDOW_MIN)
        meal_window = in_win.any(axis=2)
        meal_known = (in_win & known[:, None, :]).any(axis=2)
        hr = None
        if hr_minutes is not None:
            h = hr_minutes[hr_minutes["participant_id"] == pid].sort_values("minute")
            if len(h):
                hr = _hr_window_means(_minutes(h["minute"]), h["hr"].to_numpy(dtype=float), t0)
            else:
                hr = np.full((len(idx), 2), np.nan)
        parts.append(Samples(np.full(len(idx), pid, dtype=object), ts0.to_numpy(), v[idx], hist, base, meal,
                             hr, y, meal_window, meal_known, horizons))
    if not parts:
        raise ValueError("no samples built")
    cat = lambda name: np.concatenate([getattr(p, name) for p in parts])
    hr_all = None if hr_minutes is None else np.concatenate([p.hr for p in parts])
    return Samples(cat("pid"), cat("t0"), cat("last"), cat("hist"), cat("base"), cat("meal"), hr_all,
                   cat("y"), cat("meal_window"), cat("meal_known"), horizons)


# ----------------------------------------------------------------------------------------------
# Ridge (closed form, standardized features, unpenalized intercept)
# ----------------------------------------------------------------------------------------------
def fit_ridge(X: np.ndarray, y: np.ndarray, alpha: float = C.RIDGE_ALPHA):
    mu = X.mean(axis=0)
    sd = X.std(axis=0)
    sd[sd < 1e-9] = 1.0
    Z = (X - mu) / sd
    y_mu = float(y.mean())
    A = Z.T @ Z + alpha * np.eye(Z.shape[1])
    beta = np.linalg.solve(A, Z.T @ (y - y_mu))
    return mu, sd, beta, y_mu


def predict_ridge(params, X: np.ndarray) -> np.ndarray:
    mu, sd, beta, y_mu = params
    return ((X - mu) / sd) @ beta + y_mu


def ramp_weight(k_index: int) -> float:
    """Weight of the ramped meal columns (config.MEAL_COL_RAMP_MIN) at a horizon: 1 up to the first value,
    0 from the second, linear in between. 1 when nothing is ramped."""
    if not C.MEAL_COL_RAMP_MIN:
        return 1.0
    ramps = {tuple(v) for c, v in C.MEAL_COL_RAMP_MIN.items() if c in C.MEAL_COLS}
    if not ramps:
        return 1.0
    assert len(ramps) == 1, "ramped meal columns must share one ramp"
    full_until, zero_from = ramps.pop()
    h = (k_index + 1) * C.STEP_MIN
    if h <= full_until:
        return 1.0
    if h >= zero_from:
        return 0.0
    return (zero_from - h) / (zero_from - full_until)


def design_for(s: Samples, feature_set: str, k_index: int, hr_fill: np.ndarray | None = None,
               zero_ramped: bool = False) -> np.ndarray:
    meal = s.meal if feature_set in ("cgm_meals", "cgm_meals_hr") else None
    hr = None
    if feature_set == "cgm_meals_hr":
        hr = s.hr.copy()
        if hr_fill is not None:
            hr = np.where(np.isnan(hr), hr_fill[None, :], hr)
    if meal is not None and zero_ramped:
        off = [j for j, c in enumerate(C.MEAL_COLS) if c in C.MEAL_COL_RAMP_MIN]
        if off:
            mk = np.array(meal[:, k_index, :], dtype=float)
            for j in off:
                mk[:, 2 * j] = 0.0
                mk[:, 2 * j + 1] = 0.0
            blocks = [s.base, mk] + ([hr] if hr is not None else [])
            return np.column_stack(blocks).astype(float)
    return design(s.base, meal, hr, k_index).astype(float)


def _raw_space(params):
    """Ridge params as (mean 0, scale 1, coefficients on raw features, intercept): blends of models stay linear."""
    mu, sd, beta, y_mu = params
    coef = beta / sd
    return np.zeros_like(mu), np.ones_like(sd), coef, float(y_mu - (mu * coef).sum())


def fit_horizons(s: Samples, feature_set: str, k_indices, alpha: float = C.RIDGE_ALPHA):
    """Fit one ridge per horizon index. Returns {k_index: params}, plus the HR fill values used.

    Ramped meal columns (config.MEAL_COL_RAMP_MIN): where their weight w is below 1, a second ridge is fitted with
    those columns zeroed, and the saved model is w * full + (1 - w) * without them, folded into one linear model.
    At w = 0 that is exactly the model without the columns, and the forecast curve has no step at the ramp."""
    hr_fill = None
    if feature_set == "cgm_meals_hr":
        hr_fill = np.nanmean(s.hr, axis=0)
    models = {}
    for ki in k_indices:
        ok = ~np.isnan(s.y[:, ki])
        w = ramp_weight(ki) if feature_set != "cgm" else 1.0
        if w >= 1.0:
            models[ki] = fit_ridge(design_for(s, feature_set, ki, hr_fill)[ok], s.y[ok, ki], alpha)
            continue
        without = fit_ridge(design_for(s, feature_set, ki, hr_fill, zero_ramped=True)[ok], s.y[ok, ki], alpha)
        if w <= 0.0:
            models[ki] = without
            continue
        full = fit_ridge(design_for(s, feature_set, ki, hr_fill)[ok], s.y[ok, ki], alpha)
        a, b = _raw_space(full), _raw_space(without)
        models[ki] = (a[0], a[1], w * a[2] + (1 - w) * b[2], w * a[3] + (1 - w) * b[3])
    return models, hr_fill


def predict_horizons(models, s: Samples, feature_set: str, hr_fill=None) -> np.ndarray:
    """(n, H) predicted change from last; NaN for horizons without a model."""
    out = np.full(s.y.shape, np.nan)
    for ki, params in models.items():
        out[:, ki] = predict_ridge(params, design_for(s, feature_set, ki, hr_fill))
    return out


def fit_cgm_only(s: Samples, k_indices) -> dict:
    """The published CGM-only method extended to every horizon (D-33): the last 24 raw readings, standardized,
    ordinary least squares (a ridge with alpha 1e-6), absolute glucose at the target time."""
    y_abs = s.y + s.last[:, None]
    models = {}
    for ki in k_indices:
        ok = ~np.isnan(y_abs[:, ki])
        models[ki] = fit_ridge(s.hist[ok], y_abs[ok, ki], alpha=1e-6)
    return models


def predict_cgm_only(models: dict, s: Samples) -> np.ndarray:
    """(n, H) absolute glucose from fit_cgm_only models; NaN for horizons without a model."""
    out = np.full(s.y.shape, np.nan)
    for ki, params in models.items():
        out[:, ki] = predict_ridge(params, s.hist)
    return out


def band_quantiles(resid: np.ndarray, meal_known: np.ndarray, q=C.BAND_Q) -> np.ndarray:
    """resid (n, H) = actual - predicted. Returns (2 windows [quiet, meal], 2 quantiles, H)."""
    H = resid.shape[1]
    out = np.full((2, 2, H), np.nan)
    for w, mask in enumerate([~meal_known, meal_known]):
        for k in range(H):
            r = resid[mask[:, k], k]
            r = r[~np.isnan(r)]
            if len(r) < 30:   # too few: fall back to all windows
                r = resid[:, k][~np.isnan(resid[:, k])]
            if len(r):
                out[w, :, k] = np.quantile(r, q)
    return out


# ----------------------------------------------------------------------------------------------
# Artifact
# ----------------------------------------------------------------------------------------------
def export_artifact(out_dir: str | Path, models: dict, bands: np.ndarray, feature_set: str, meta: dict) -> Path:
    """Save coefficients for every horizon 1..MAX_H plus bands and metadata (numpy .npz + JSON)."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    H = len(models)
    names = feature_names(feature_set, C.MEAL_COLS)
    F = len(names)
    mu = np.zeros((H, F)); sd = np.ones((H, F)); beta = np.zeros((H, F)); icpt = np.zeros(H)
    for ki in range(H):
        m, s, b, y_mu = models[ki]
        mu[ki], sd[ki], beta[ki], icpt[ki] = m, s, b, y_mu
    np.savez(out_dir / "model.npz", x_mean=mu, x_scale=sd, coef=beta, intercept=icpt, bands=bands)
    meta = dict(meta)
    meta.update({
        "version": C.VERSION,
        "feature_set": feature_set,
        "feature_names": names,
        "horizons_steps": list(range(1, H + 1)),
        "step_min": C.STEP_MIN,
        "history": C.HISTORY,
        "kernel_shape": C.KERNEL_SHAPE,
        "kernel_peak_min": C.KERNEL_PEAK_MIN,
        "meal_cols": C.MEAL_COLS,
        "meal_col_ramp_min": C.MEAL_COL_RAMP_MIN,
        "big_meal_carbs_g": C.BIG_MEAL_CARBS_G,
        "morning_end_hour": C.MORNING_END_HOUR,
        "band_quantiles": list(C.BAND_Q),
        "exported_at": datetime.now(timezone.utc).isoformat(),
    })
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2, default=str))
    return out_dir


def _stack(models: dict, H: int, F: int):
    mu = np.zeros((H, F)); sd = np.ones((H, F)); beta = np.zeros((H, F)); icpt = np.zeros(H)
    for ki in range(H):
        m, sdev, b, y_mu = models[ki]
        mu[ki], sd[ki], beta[ki], icpt[ki] = m, sdev, b, y_mu
    return mu, sd, beta, icpt


def export_bundle(out_dir: str | Path, components: dict, feature_set: str, fold_map: dict, meta: dict) -> Path:
    """Save the full model, the fold models and the participant-to-fold map in one artifact (CONTRACT section 8, D-26).

    components: name ("full", "fold0", ...) -> {"models", "bands", "cgm_models", "cgm_bands",
    "training_participants"}. model.npz holds "<name>__<array>" for every component (plus the full model under the
    plain names, so older loaders still work); meta.json holds the fold map and each component's participants.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    names = feature_names(feature_set, C.MEAL_COLS)
    arrays, comp_meta = {}, {}
    for cname, comp in components.items():
        H = len(comp["models"])
        mu, sd, beta, icpt = _stack(comp["models"], H, len(names))
        cmu, csd, cbeta, cicpt = _stack(comp["cgm_models"], H, C.HISTORY)
        for key, arr in (("x_mean", mu), ("x_scale", sd), ("coef", beta), ("intercept", icpt),
                         ("bands", comp["bands"]), ("cgm_x_mean", cmu), ("cgm_x_scale", csd),
                         ("cgm_coef", cbeta), ("cgm_intercept", cicpt), ("cgm_bands", comp["cgm_bands"])):
            arrays[f"{cname}__{key}"] = arr
            if cname == "full":
                arrays[key] = arr
        comp_meta[cname] = {"training_participants": sorted(comp["training_participants"]),
                            "fold": None if cname == "full" else int(cname.replace("fold", ""))}
    np.savez(out_dir / "model.npz", **arrays)
    meta = dict(meta)
    meta.update({
        "version": C.VERSION,
        "feature_set": feature_set,
        "feature_names": names,
        "horizons_steps": list(range(1, len(components["full"]["models"]) + 1)),
        "step_min": C.STEP_MIN,
        "history": C.HISTORY,
        "kernel_shape": C.KERNEL_SHAPE,
        "kernel_peak_min": C.KERNEL_PEAK_MIN,
        "meal_cols": C.MEAL_COLS,
        "meal_col_ramp_min": C.MEAL_COL_RAMP_MIN,
        "big_meal_carbs_g": C.BIG_MEAL_CARBS_G,
        "morning_end_hour": C.MORNING_END_HOUR,
        "band_quantiles": list(C.BAND_Q),
        "fold_map": {str(k): int(v) for k, v in fold_map.items()},
        "components": comp_meta,
        "cgm_only": "published CGM-only linear method per horizon: last 24 readings, standardized, least squares (D-33)",
        "exported_at": datetime.now(timezone.utc).isoformat(),
    })
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2, default=str))
    return out_dir
