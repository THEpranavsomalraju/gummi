"""Reproduce the published CGM-only baseline (Seyedebrahimi et al. 2026, PhysioFusion code).

Protocol (copied from PhysioFusion, see reports/prior_work.md):
- islands split at gaps > 15 min; windows never cross an island
- history = 24 readings; target = the reading 6 steps after the last history reading (30 min)
- 5-fold GroupKFold on participant id; StandardScaler + LinearRegression
- persistence = last history value; mean = training-fold mean of y
Published: LR 13.90 +/- 0.58, persistence 16.49, mean 22.76 (15 subjects, 015 excluded).
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import GroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


def windows(silver_cgm: pd.DataFrame, history: int = 24, horizon: int = 6):
    """X (n, history), y (n,), groups (n,) built island by island, participant by participant."""
    Xs, ys, gs = [], [], []
    for (pid, _), isl in silver_cgm.sort_values("ts").groupby(["participant_id", "island"], sort=True):
        g = isl["glucose"].to_numpy(dtype=float)
        n = len(g)
        if n < history + horizon:
            continue
        idx = np.arange(0, n - history - horizon + 1)
        X = np.stack([g[i:i + history] for i in idx])
        y = g[idx + history + horizon - 1]
        ok = ~np.isnan(X).any(axis=1) & ~np.isnan(y)
        Xs.append(X[ok]); ys.append(y[ok]); gs.append(np.full(ok.sum(), pid, dtype=object))
    return np.concatenate(Xs), np.concatenate(ys), np.concatenate(gs)


def assert_no_leakage(groups, train_idx, test_idx) -> None:
    overlap = set(np.asarray(groups)[train_idx]) & set(np.asarray(groups)[test_idx])
    if overlap:
        raise AssertionError(f"participants in both train and test: {sorted(overlap)}")


def baseline_repro(silver_cgm: pd.DataFrame, exclude: tuple[str, ...] = ("015",), n_splits: int = 5,
                   history: int = 24, horizon: int = 6) -> pd.DataFrame:
    """Per-fold RMSE/MAE for mean, persistence and linear regression. Returns one row per (fold, model)."""
    data = silver_cgm[~silver_cgm["participant_id"].isin(exclude)]
    X, y, groups = windows(data, history, horizon)
    rows = []
    for fold, (tr, te) in enumerate(GroupKFold(n_splits=n_splits).split(X, y, groups)):
        assert_no_leakage(groups, tr, te)
        preds = {
            "mean": np.full(len(te), y[tr].mean()),
            "persistence": X[te, -1],
            "linear_regression": make_pipeline(StandardScaler(), LinearRegression()).fit(X[tr], y[tr]).predict(X[te]),
        }
        for name, p in preds.items():
            err = y[te] - p
            rows.append({
                "fold": fold, "model": name, "n_test": len(te),
                "test_participants": ",".join(sorted(set(groups[te]))),
                "rmse": float(np.sqrt(np.mean(err ** 2))), "mae": float(np.mean(np.abs(err))),
            })
    return pd.DataFrame(rows)


def summarize(per_fold: pd.DataFrame) -> pd.DataFrame:
    s = per_fold.groupby("model").agg(rmse_mean=("rmse", "mean"), rmse_sd=("rmse", lambda v: np.std(v)),
                                      mae_mean=("mae", "mean"), n_windows=("n_test", "sum"))
    s["published_rmse"] = s.index.map({"linear_regression": 13.90, "persistence": 16.49, "mean": 22.76})
    return s.round(2).sort_values("rmse_mean")
