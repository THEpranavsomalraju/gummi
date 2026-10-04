"""Big-spike under-prediction experiment (Backend REQUEST 2010, ask B). Participant-grouped, same folds as everything else.

Each variant changes only the meal features or the loss; the CGM part, folds and evaluation code stay the same.
For every variant: MAE and RMSE by horizon and window with fold spread, and the meal-time table the app sees
(peak bias, peak error, curve error, how often the forecast and the truth cross 140 mg/dL).

    python data/scripts/spike_experiment.py --raw data/raw/bigideas_1.1.3 --out data/local_out/spike_experiment
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

from bigideas import build_silver_cgm, build_silver_meals  # noqa: E402
from bigideas.baseline import windows  # noqa: E402
from gummi_model import config as C  # noqa: E402
from gummi_model import evaluate as E  # noqa: E402
from gummi_model import train as T  # noqa: E402
from gummi_model.train import build_samples  # noqa: E402

BASE = list(C.INPUT_MACROS)
VARIANTS = {
    "v0_current": {"cols": BASE},
    "b_carbs_hinge": {"cols": BASE + ["carbs_big_g"]},
    "b_carbs_sugar_hinge": {"cols": BASE + ["carbs_big_g", "sugar_big_g"]},
    "b_multi_kernel": {"cols": BASE + ["carbs_fast_g", "carbs_slow_g"]},
    "b_multi_kernel_hinge": {"cols": BASE + ["carbs_fast_g", "carbs_slow_g", "carbs_big_g", "sugar_big_g"]},
    "b_hinge30": {"cols": BASE + ["carbs_big_g"], "big_carbs": 30.0},
    "b_hinge60": {"cols": BASE + ["carbs_big_g"], "big_carbs": 60.0},
    "b_hinge40_k75": {"cols": BASE + ["carbs_big_g"], "big_peak": 75.0},
    "b_hinge40_k40": {"cols": BASE + ["carbs_big_g"], "big_peak": 40.0},
    "b_hinge_to120": {"cols": BASE + ["carbs_big_g"], "ramp": {"carbs_big_g": (120, 125)}},
    "b_hinge_to150": {"cols": BASE + ["carbs_big_g"], "ramp": {"carbs_big_g": (150, 155)}},
    "b_hinge_ramp120_180": {"cols": BASE + ["carbs_big_g"], "ramp": {"carbs_big_g": (120, 180)}},
    "b_hinge_ramp150_180": {"cols": BASE + ["carbs_big_g"], "ramp": {"carbs_big_g": (150, 180)}},
}
HORIZONS = (30, 60, 90, 120, 180)


def run_variant(name, spec, cgm, meals, folds, log):
    from gummi_model import features as F
    C.MEAL_COLS[:] = spec["cols"]                     # every module reads the same list object
    F.BIG_MEAL_CARBS_G = C.BIG_MEAL_CARBS_G = spec.get("big_carbs", 40.0)
    C.KERNEL_PEAK_MIN["carbs_big_g"] = spec.get("big_peak", 55.0)   # one dict object shared by every module
    C.MEAL_COL_RAMP_MIN.clear(); C.MEAL_COL_RAMP_MIN.update(spec.get("ramp", {}))
    t0 = time.time()
    samples = build_samples(cgm, meals)
    k_eval = [h // C.STEP_MIN - 1 for h in HORIZONS]
    pf = E.evaluate(samples, folds, feature_sets=("cgm_meals",), k_indices=k_eval, with_bands=False)
    pf = pf[pf.model.isin(["gummi_cgm_meals", "cgm_only", "persistence"])]
    mp = E.meal_prediction_eval(samples, folds, cgm, meals, feature_sets=("cgm_meals",), meta={})
    mp = mp[mp.model == "gummi_cgm_meals"]
    log(f"{name}: {time.time() - t0:.0f}s")
    return pf.assign(variant=name), mp.assign(variant=name)


def meal_table(mp: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (v, sub), g in pd.concat([mp.assign(sub="all"), mp[mp.carbs_g >= 40].assign(sub="40g+"),
                                  mp[mp.is_standard_breakfast].assign(sub="std_breakfast")]).groupby(["variant", "sub"]):
        bias = g.predicted_peak - g.actual_peak
        hi = g.actual_peak >= 140
        rows.append({"variant": v, "subset": sub, "meals": len(g),
                     "peak_bias": round(bias.mean(), 1), "peak_mae": round(bias.abs().mean(), 1),
                     "curve_mae": round(g.curve_mae.mean(), 2),
                     "actual_140": int(hi.sum()), "pred_140_when_actual_140": int((g.predicted_peak[hi] >= 140).sum()),
                     "pred_140_false": int(((g.predicted_peak >= 140) & ~hi).sum()),
                     "fold_peak_bias": [round(x, 1) for x in g.assign(b=bias).groupby("fold").b.mean()]})
    return pd.DataFrame(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(DATA / "raw" / "bigideas_1.1.3"))
    ap.add_argument("--out", default=str(DATA / "local_out" / "spike_experiment"))
    ap.add_argument("--variants", nargs="*", default=list(VARIANTS))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cgm = build_silver_cgm(args.raw)
    meals = build_silver_meals(args.raw)
    cgm = cgm[cgm.participant_id != "015"]
    _, _, groups = windows(cgm)
    folds = E.fold_map(groups)
    pfs, mps = [], []
    for v in args.variants:
        pf, mp = run_variant(v, VARIANTS[v], cgm, meals, folds, print)
        pfs.append(pf); mps.append(mp)
        pd.concat(pfs).to_csv(out / "per_fold.csv", index=False)
        pd.concat(mps).to_csv(out / "meal_predictions.csv", index=False)
    pf, mp = pd.concat(pfs), pd.concat(mps)
    s = pf.groupby(["variant", "model", "horizon_min", "window"]).agg(
        mae=("mae", "mean"), mae_sd=("mae", "std"), rmse=("rmse", "mean"), rmse_sd=("rmse", "std")).round(2).reset_index()
    s.to_csv(out / "summary.csv", index=False)
    mt = meal_table(mp)
    mt.to_csv(out / "meal_table.csv", index=False)
    g = s[s.model == "gummi_cgm_meals"].pivot_table(index=["window", "horizon_min"], columns="variant", values="mae")
    print("Gummi MAE by window and horizon:\n", g[args.variants].to_string())
    print(mt.to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
