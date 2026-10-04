"""Backend REQUEST 2310, item 2: a per-horizon blend y = w_h * Gummi + (1 - w_h) * CGM-only.

Nested and participant-grouped, so the numbers stay honest: for each of the 5 outer folds, w_h is chosen on an inner
4-fold participant-grouped CV over that fold's training people only (lowest MAE over a grid of w from 0 to 1), with
separate weights for targets inside a known meal window and quiet ones. The blend's bands come from the same inner
out-of-fold residuals. The outer fold then scores Gummi alone and the blend on people never used to pick w.

    python data/scripts/blend_experiment.py --raw data/raw/bigideas_1.1.3 --out data/local_out/blend_experiment
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupKFold

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

from bigideas import build_silver_cgm, build_silver_meals  # noqa: E402
from bigideas.baseline import windows  # noqa: E402
from gummi_model import config as C  # noqa: E402
from gummi_model import evaluate as E  # noqa: E402
from gummi_model.train import (band_quantiles, build_samples, fit_cgm_only, fit_horizons, predict_cgm_only,  # noqa: E402
                               predict_horizons)

KS = list(range(36))                       # every 5-minute step to 180 minutes
REPORT = (30, 60, 90, 120, 180)
GRID = np.round(np.linspace(0, 1, 21), 2)


def both(tr, te):
    """Absolute-glucose predictions of Gummi and CGM-only fitted on tr, for te, every step in KS."""
    g, _ = fit_horizons(tr, "cgm_meals", KS)
    pg = predict_horizons(g, te, "cgm_meals") + te.last[:, None]
    pc = predict_cgm_only(fit_cgm_only(tr, KS), te)
    return pg, pc


def choose_weights(s):
    """Inner participant-grouped OOF on s: w per (window, step) by lowest MAE, plus the blend's OOF residuals."""
    pg = np.full(s.y.shape, np.nan); pc = np.full(s.y.shape, np.nan)
    for a, b in GroupKFold(n_splits=4).split(np.zeros(len(s)), groups=s.pid):
        m = np.zeros(len(s), bool); m[b] = True
        x, y = both(s.subset(~m), s.subset(m))
        pg[m], pc[m] = x, y
    truth = s.y + s.last[:, None]
    w = np.ones((2, s.y.shape[1]))
    for k in KS:
        for win in (0, 1):
            sel = (s.meal_known[:, k].astype(int) == win) & ~np.isnan(truth[:, k])
            if sel.sum() < 50:
                continue
            maes = [np.mean(np.abs(g * pg[sel, k] + (1 - g) * pc[sel, k] - truth[sel, k])) for g in GRID]
            w[win, k] = GRID[int(np.argmin(maes))]
    wi = s.meal_known.astype(int)
    blend = np.where(wi == 1, w[1][None, :], w[0][None, :]) * pg + (1 - np.where(wi == 1, w[1][None, :], w[0][None, :])) * pc
    bands = band_quantiles(truth - blend, s.meal_known)
    gb = band_quantiles(truth - pg, s.meal_known)
    return w, bands, gb


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(DATA / "raw" / "bigideas_1.1.3"))
    ap.add_argument("--out", default=str(DATA / "local_out" / "blend_experiment"))
    args = ap.parse_args()
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    cgm = build_silver_cgm(args.raw); meals = build_silver_meals(args.raw)
    cgm = cgm[cgm.participant_id != "015"]
    _, _, groups = windows(cgm)
    folds = E.fold_map(groups)
    s = build_samples(cgm, meals)
    fold_of = np.array([folds[p] for p in s.pid])
    rows, weights = [], {}
    for f in sorted(set(folds.values())):
        tr, te = s.subset(fold_of != f), s.subset(fold_of == f)
        w, bands, gbands = choose_weights(tr)
        weights[f] = {"quiet": w[0].tolist(), "meal": w[1].tolist()}
        pg, pc = both(tr, te)
        wi = te.meal_known.astype(int)
        W = np.where(wi == 1, w[1][None, :], w[0][None, :])
        pb = W * pg + (1 - W) * pc
        truth = te.y + te.last[:, None]
        for h in REPORT:
            k = h // C.STEP_MIN - 1
            for window, wm in (("all", np.ones(len(te), bool)), ("meal", te.meal_window[:, k]),
                               ("quiet", ~te.meal_window[:, k])):
                ok = wm & ~np.isnan(truth[:, k])
                for name, p, bd in (("gummi", pg, gbands), ("blend", pb, bands), ("cgm_only", pc, None)):
                    e = p[ok, k] - truth[ok, k]
                    cov = np.nan
                    if bd is not None:
                        lo = p[ok, k] + bd[wi[ok, k], 0, k]; hi = p[ok, k] + bd[wi[ok, k], 1, k]
                        cov = float(np.mean((truth[ok, k] >= lo) & (truth[ok, k] <= hi)))
                    rows.append({"fold": f, "model": name, "horizon_min": h, "window": window, "n": int(ok.sum()),
                                 "mae": float(np.mean(np.abs(e))), "rmse": float(np.sqrt(np.mean(e ** 2))),
                                 "coverage": cov})
        print(f"fold {f} done; w at 60 min quiet/meal: {w[0][11]}/{w[1][11]}", flush=True)
    pf = pd.DataFrame(rows)
    pf.to_csv(out / "per_fold.csv", index=False)
    json.dump(weights, open(out / "weights_by_fold.json", "w"))
    s1 = pf.groupby(["window", "horizon_min", "model"]).agg(mae=("mae", "mean"), mae_sd=("mae", "std"),
                                                          coverage=("coverage", "mean")).round(3).reset_index()
    s1.to_csv(out / "summary.csv", index=False)
    piv = s1.pivot_table(index=["window", "horizon_min"], columns="model", values="mae")
    a = pf[pf.model == "blend"].set_index(["fold", "window", "horizon_min"]).mae
    b = pf[pf.model == "gummi"].set_index(["fold", "window", "horizon_min"]).mae
    piv["blend_minus_gummi"] = (piv["blend"] - piv["gummi"]).round(3)
    piv["folds_blend_better"] = ((a - b) < -1e-9).groupby(level=["window", "horizon_min"]).sum()
    cov = s1.pivot_table(index=["window", "horizon_min"], columns="model", values="coverage")
    piv["cov_gummi"] = cov["gummi"].round(3); piv["cov_blend"] = cov["blend"].round(3)
    print(piv.to_string())
    for f, wd in weights.items():
        print(f, "quiet w at 30/60/120/180:", [wd["quiet"][h // 5 - 1] for h in REPORT],
              "meal:", [wd["meal"][h // 5 - 1] for h in REPORT])
    return 0


if __name__ == "__main__":
    sys.exit(main())
