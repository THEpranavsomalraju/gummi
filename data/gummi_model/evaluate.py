"""Participant-grouped evaluation, baselines, meal ablation, and band coverage.

Folds are assigned per participant once (GroupKFold over the published-baseline windows) and reused,
so Gummi and the published baseline are scored on the same held-out people.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupKFold

from . import config as C
from .train import (Samples, band_quantiles, fit_cgm_only, fit_horizons, fit_ridge, predict_cgm_only,
                    predict_horizons, predict_ridge)

EVAL_MINUTES = (30, 60, 90, 120, 180)
EVAL_K = [m // C.STEP_MIN - 1 for m in EVAL_MINUTES]      # horizon index (k-1)


def fold_map(groups: np.ndarray, n_splits: int = 5) -> dict[str, int]:
    """participant -> fold, from GroupKFold over window-level groups (same as the baseline repro)."""
    groups = np.asarray(groups)
    out = {}
    for f, (_, te) in enumerate(GroupKFold(n_splits=n_splits).split(np.zeros(len(groups)), groups=groups)):
        for p in sorted(set(groups[te])):          # sorted: same row order on every run
            out[p] = f
    return out


def _metrics(err: np.ndarray) -> dict:
    err = err[~np.isnan(err)]
    if len(err) == 0:
        return {"n": 0, "rmse": np.nan, "mae": np.nan}
    return {"n": int(len(err)), "rmse": float(np.sqrt(np.mean(err ** 2))), "mae": float(np.mean(np.abs(err)))}


def _oof_bands(train: Samples, feature_set: str, k_indices, inner_splits: int = 4) -> np.ndarray:
    """Band quantiles from inner participant-grouped CV on the training participants only."""
    pids = np.unique(train.pid)
    n_inner = min(inner_splits, len(pids))
    resid = np.full(train.y.shape, np.nan)
    for _, te in GroupKFold(n_splits=n_inner).split(np.zeros(len(train)), groups=train.pid):
        mask = np.zeros(len(train), bool); mask[te] = True
        tr_s, te_s = train.subset(~mask), train.subset(mask)
        models, fill = fit_horizons(tr_s, feature_set, k_indices)
        pred = predict_horizons(models, te_s, feature_set, fill)
        resid[mask] = te_s.y - pred
    return band_quantiles(resid, train.meal_known)


def evaluate(samples: Samples, folds: dict[str, int], feature_sets=("cgm", "cgm_meals"),
             k_indices=EVAL_K, with_bands: bool = True) -> pd.DataFrame:
    """Rows: fold, model, horizon_min, window (all/meal/quiet), n, rmse, mae, coverage (Gummi models only).

    Baselines on the same samples: mean (training-fold mean glucose at that horizon), persistence
    (last value), and CGM-only linear regression on the 24 raw readings (the published method).
    """
    rows = []
    fold_of = np.array([folds[p] for p in samples.pid])
    for f in sorted(set(folds.values())):
        tr_s, te_s = samples.subset(fold_of != f), samples.subset(fold_of == f)
        y_abs_te = te_s.y + te_s.last[:, None]
        preds = {}
        for fs in feature_sets:
            models, fill = fit_horizons(tr_s, fs, k_indices)
            preds[fs] = (predict_horizons(models, te_s, fs, fill) + te_s.last[:, None],
                         _oof_bands(tr_s, fs, k_indices) if with_bands else None)
        # baselines
        base_pred = {"persistence": np.repeat(te_s.last[:, None], te_s.y.shape[1], axis=1)}
        y_abs_tr = tr_s.y + tr_s.last[:, None]
        base_pred["mean"] = np.repeat(np.nanmean(y_abs_tr, axis=0)[None, :], len(te_s), axis=0)
        base_pred["cgm_only"] = predict_cgm_only(fit_cgm_only(tr_s, k_indices), te_s)   # published method, D-33
        for ki in k_indices:
            for window, wmask in (("all", np.ones(len(te_s), bool)), ("meal", te_s.meal_window[:, ki]),
                                  ("quiet", ~te_s.meal_window[:, ki])):
                truth = y_abs_te[wmask, ki]
                for name, p in base_pred.items():
                    rows.append({"fold": f, "model": name, "horizon_min": (ki + 1) * C.STEP_MIN, "window": window,
                                 **_metrics(truth - p[wmask, ki]), "coverage": np.nan})
                for fs, (p, bands) in preds.items():
                    cov = np.nan
                    if bands is not None:
                        wi = te_s.meal_known[wmask, ki].astype(int)        # band chosen from known meals
                        lo = p[wmask, ki] + bands[wi, 0, ki]
                        hi = p[wmask, ki] + bands[wi, 1, ki]
                        ok = ~np.isnan(truth)
                        cov = float(np.mean((truth[ok] >= lo[ok]) & (truth[ok] <= hi[ok]))) if ok.any() else np.nan
                    rows.append({"fold": f, "model": f"gummi_{fs}", "horizon_min": (ki + 1) * C.STEP_MIN,
                                 "window": window, **_metrics(truth - p[wmask, ki]), "coverage": cov})
    return pd.DataFrame(rows)


def meal_prediction_eval(samples: Samples, folds: dict[str, int], silver_cgm: pd.DataFrame,
                         silver_meals: pd.DataFrame, feature_sets=("cgm", "cgm_meals"), delay_min: int = C.DELAY_MIN,
                         window_min: int = 120, meta: dict | None = None) -> pd.DataFrame:
    """What the app shows: a meal is logged at time e, Gummi predicts the next `window_min` minutes with
    confirmed data only up to e - delay. One row per (held-out meal, model) with the predicted and actual peak,
    the last-value guess (last confirmed reading at e), and curve MAE for Gummi and the last-value guess.
    Participant-grouped: each meal is predicted by models trained without that participant.
    """
    from .model import GlucoseModel, UserContext   # local import: evaluation-only path
    rows = []
    fold_of = np.array([folds[p] for p in samples.pid])
    all_k = list(range(C.MAX_H))
    for f in sorted(set(folds.values())):
        tr = samples.subset(fold_of != f)
        models = {}
        cgm_fit = fit_cgm_only(tr, all_k)
        for fs in feature_sets:
            fit, _ = fit_horizons(tr, fs, all_k)
            zero_bands = np.zeros((2, 2, C.MAX_H))
            models[fs] = GlucoseModel.from_fit(fit, zero_bands, fs, meta, cgm_models=cgm_fit)
        test_pids = [p for p, ff in folds.items() if ff == f]
        for pid in test_pids:
            g = silver_cgm[silver_cgm["participant_id"] == pid].sort_values("ts")
            cg = pd.DataFrame({"t": g["ts"].dt.tz_localize("UTC"), "glucose_mg_dl": g["glucose"].to_numpy()})
            pm = silver_meals[silver_meals["participant_id"] == pid].copy()
            pm["eaten_at"] = pm["eaten_at"].dt.tz_localize("UTC")
            for _, meal in pm.iterrows():
                e = meal["eaten_at"]
                hist = cg[cg["t"] <= e - pd.Timedelta(minutes=delay_min)]
                win = cg[(cg["t"] >= e) & (cg["t"] <= e + pd.Timedelta(minutes=window_min))]
                if len(hist) < C.HISTORY or len(win) < int(0.8 * window_min / C.STEP_MIN):
                    continue
                if (hist["t"].iloc[-1] < e - pd.Timedelta(minutes=delay_min + 15)):
                    continue                                   # data gap right before the meal
                ctx_meals = pm[pm["eaten_at"] <= e][["eaten_at"] + C.INPUT_MACROS]
                last_value = float(hist["glucose_mg_dl"].iloc[-1])
                actual_peak = float(win["glucose_mg_dl"].max())
                ctx = UserContext(f"p_{pid}", {}, hist, ctx_meals, None, None)
                n_gap = int((e - hist["t"].iloc[-1]).total_seconds() // 300)
                curves = {}
                for fs, model in models.items():
                    arr = model._forecast_arrays(ctx, e, window_min)
                    gap = model._predict(ctx, e, np.arange(1, n_gap + 1))
                    curves[f"gummi_{fs}"] = (np.concatenate([gap[2], arr[0]]), np.concatenate([gap[3], arr[1]]))
                any_model = next(iter(models.values()))
                c_t, c_v, _, _ = any_model._cgm_only_arrays(ctx, e, np.arange(1, n_gap + window_min // C.STEP_MIN + 1))
                curves["cgm_only"] = (c_t, c_v)                  # the published CGM-only method, same fold (D-33)
                e_min = e.timestamp() / 60.0
                w_t = (win["t"] - pd.Timestamp("1970-01-01", tz="UTC")).dt.total_seconds().to_numpy() / 60.0
                for name, (tgt, val) in curves.items():
                    in_win = (tgt >= e_min) & (tgt <= e_min + window_min)
                    pred_t, pred_v = tgt[in_win], val[in_win]
                    j = np.clip(np.searchsorted(w_t, pred_t), 1, len(w_t) - 1)
                    jj = np.where(np.abs(w_t[j - 1] - pred_t) <= np.abs(w_t[j] - pred_t), j - 1, j)
                    hit = np.abs(w_t[jj] - pred_t) <= C.MATCH_TOL_MIN
                    actual = win["glucose_mg_dl"].to_numpy()[jj][hit]
                    rows.append({
                        "fold": f, "participant_id": pid, "meal_id": meal["meal_id"], "model": name,
                        "carbs_g": meal["carbs_g"], "is_standard_breakfast": bool(meal.get("is_standard_breakfast", False)),
                        "predicted_peak": float(pred_v.max()), "actual_peak": actual_peak, "last_value": last_value,
                        "peak_abs_err": abs(float(pred_v.max()) - actual_peak),
                        "last_value_peak_abs_err": abs(last_value - actual_peak),
                        "curve_mae": float(np.mean(np.abs(pred_v[hit] - actual))) if hit.any() else np.nan,
                        "last_value_curve_mae": float(np.mean(np.abs(last_value - actual))) if hit.any() else np.nan,
                    })
    return pd.DataFrame(rows)


def summarize_meal_predictions(mp: pd.DataFrame) -> pd.DataFrame:
    """Per model: peak and curve errors next to the last-value guess, the signed peak error (negative = Gummi
    predicted a lower peak than happened), and the share of meals where Gummi's curve beat the last-value guess."""
    mp = mp.assign(peak_signed=mp["predicted_peak"] - mp["actual_peak"],
                   win=(mp["curve_mae"] < mp["last_value_curve_mae"]).astype(float))
    out = mp.groupby("model").agg(
        meals=("meal_id", "count"), peak_mae=("peak_abs_err", "mean"),
        last_value_peak_mae=("last_value_peak_abs_err", "mean"), peak_bias=("peak_signed", "mean"),
        curve_mae=("curve_mae", "mean"), last_value_curve_mae=("last_value_curve_mae", "mean"),
        gummi_beats_last_value_pct=("win", "mean")).reset_index()
    out["gummi_beats_last_value_pct"] *= 100
    return out.round(1)


def summarize(per_fold: pd.DataFrame) -> pd.DataFrame:
    g = per_fold.groupby(["model", "horizon_min", "window"])
    out = g.agg(rmse_mean=("rmse", "mean"), rmse_sd=("rmse", "std"), mae_mean=("mae", "mean"),
                coverage=("coverage", "mean"), n=("n", "sum")).reset_index()
    return out.round(2)


def ablation_table(per_fold: pd.DataFrame, a: str = "gummi_cgm", b: str = "gummi_cgm_meals") -> pd.DataFrame:
    """Per horizon and window: RMSE of a vs b per fold, the mean difference, and how many folds b wins."""
    p = per_fold[per_fold["model"].isin([a, b])].pivot_table(
        index=["horizon_min", "window", "fold"], columns="model", values="rmse").reset_index()
    p["diff"] = p[b] - p[a]
    out = p.groupby(["horizon_min", "window"]).agg(
        rmse_a=(a, "mean"), rmse_b=(b, "mean"), diff_mean=("diff", "mean"), diff_sd=("diff", "std"),
        folds_b_better=("diff", lambda d: int((d < 0).sum())), folds=("diff", "size")).reset_index()
    out.insert(0, "comparison", f"{b} vs {a}")
    return out.round(2)


def personal_online_eval(samples: Samples, folds: dict[str, int], silver_cgm: pd.DataFrame,
                         silver_meals: pd.DataFrame, feature_set: str = "cgm_meals", meta: dict | None = None,
                         delay_min: int = C.DELAY_MIN, window_min: int = 120) -> pd.DataFrame:
    """Does the personal layer help? Each held-out person's meals in time order, predicted at logging time with data
    up to one hour before, by a population model trained without that person. Personal parameters come only from
    that person's earlier meals whose 2-hour window had closed and whose readings had arrived (eaten + 180 minutes).
    Variants per meal: none, factor (personal carb factor), factor_offset (carb factor plus a constant offset).
    """
    from .model import GlucoseModel, UserContext   # evaluation-only path
    from .personal import fit_personal, meal_terms
    rows = []
    fold_of = np.array([folds[p] for p in samples.pid])
    lag = pd.Timedelta(minutes=window_min + delay_min)
    for f in sorted(set(folds.values())):
        fit, _ = fit_horizons(samples.subset(fold_of != f), feature_set, list(range(C.MAX_H)))
        model = GlucoseModel.from_fit(fit, np.zeros((2, 2, C.MAX_H)), feature_set, meta)
        for pid in [p for p, ff in folds.items() if ff == f]:
            g = silver_cgm[silver_cgm["participant_id"] == pid].sort_values("ts")
            cg = pd.DataFrame({"t": g["ts"].dt.tz_localize("UTC"), "glucose_mg_dl": g["glucose"].to_numpy()})
            pm = silver_meals[silver_meals["participant_id"] == pid].copy()
            pm["eaten_at"] = pm["eaten_at"].dt.tz_localize("UTC")
            pm = pm.sort_values("eaten_at")
            evidence: list[tuple[pd.Timestamp, tuple]] = []     # (available_at, (c, r)) per closed meal
            for _, meal in pm.iterrows():
                e = meal["eaten_at"]
                closed = [t for at, t in evidence if at <= e]
                hist = cg[cg["t"] <= e - pd.Timedelta(minutes=delay_min)]
                win = cg[(cg["t"] >= e) & (cg["t"] <= e + pd.Timedelta(minutes=window_min))]
                usable = (len(hist) >= C.HISTORY and len(win) >= int(0.8 * window_min / C.STEP_MIN)
                          and hist["t"].iloc[-1] >= e - pd.Timedelta(minutes=delay_min + 15)) if len(hist) else False
                if usable:
                    ctx_meals = pm[pm["eaten_at"] <= e][["eaten_at"] + C.INPUT_MACROS]
                    f1, _ = fit_personal(closed, with_offset=False)
                    f2, o2 = fit_personal(closed, with_offset=True)
                    w_t = (win["t"] - pd.Timestamp("1970-01-01", tz="UTC")).dt.total_seconds().to_numpy() / 60.0
                    e_min = e.timestamp() / 60.0
                    gap_n = int((e - hist["t"].iloc[-1]).total_seconds() // 300)
                    for variant, personal in (("none", None), ("factor", {"carb_factor": f1}),
                                              ("factor_offset", {"carb_factor": f2, "offset_mg_dl": o2})):
                        ctx = UserContext(f"p_{pid}", {}, hist, ctx_meals, None, personal)
                        _, _, tgt, val, _, _, _ = model._predict(ctx, e, np.arange(1, gap_n + window_min // C.STEP_MIN + 1))
                        m = (tgt >= e_min) & (tgt <= e_min + window_min)
                        pt, pv = tgt[m], val[m]
                        j = np.clip(np.searchsorted(w_t, pt), 1, len(w_t) - 1)
                        jj = np.where(np.abs(w_t[j - 1] - pt) <= np.abs(w_t[j] - pt), j - 1, j)
                        hit = np.abs(w_t[jj] - pt) <= C.MATCH_TOL_MIN
                        actual = win["glucose_mg_dl"].to_numpy()[jj][hit]
                        rows.append({
                            "fold": f, "participant_id": pid, "meal_id": meal["meal_id"], "variant": variant,
                            "meals_learned_from": len(closed), "carb_factor": (personal or {}).get("carb_factor", 1.0),
                            "offset_mg_dl": (personal or {}).get("offset_mg_dl", 0.0), "carbs_g": meal["carbs_g"],
                            "is_standard_breakfast": bool(meal.get("is_standard_breakfast", False)),
                            "predicted_peak": float(pv.max()), "actual_peak": float(win["glucose_mg_dl"].max()),
                            "curve_mae": float(np.mean(np.abs(pv[hit] - actual))) if hit.any() else np.nan,
                        })
                seen = UserContext(f"p_{pid}", {}, cg[cg["t"] <= e + pd.Timedelta(minutes=window_min)],
                                   pm[["eaten_at"] + C.INPUT_MACROS], None, None)
                term = meal_terms(model, seen, e)
                if term is not None:
                    evidence.append((e + lag, term))
    return pd.DataFrame(rows)


def summarize_personal(pe: pd.DataFrame) -> pd.DataFrame:
    """Peak error, signed peak error and curve error per variant, for all meals and for meals after at least
    five earlier meals had closed."""
    pe = pe.assign(peak_err=(pe["predicted_peak"] - pe["actual_peak"]))
    out = []
    for subset, d in (("all meals", pe), ("after 5+ earlier meals", pe[pe["meals_learned_from"] >= 5]),
                      ("standardized breakfasts", pe[pe["is_standard_breakfast"]])):
        s = d.groupby("variant").agg(meals=("meal_id", "count"), peak_mae=("peak_err", lambda x: x.abs().mean()),
                                     peak_bias=("peak_err", "mean"), curve_mae=("curve_mae", "mean"),
                                     carb_factor_median=("carb_factor", "median")).reset_index()
        s["subset"] = subset
        out.append(s)
    return pd.concat(out, ignore_index=True).round(2)
