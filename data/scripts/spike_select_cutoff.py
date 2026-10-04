"""Nested choice of how far ahead the big-meal carb term (carbs_big_g) is used.

For each outer fold, the cutoff is picked by an inner participant-grouped CV on that fold's training participants
only (lowest mean MAE over every 5-minute horizon out to 180 minutes), so the outer-fold numbers stay honest. The shipped
cutoff is picked the same way on all 15 participants.

    python data/scripts/spike_select_cutoff.py --raw data/raw/bigideas_1.1.3
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from sklearn.model_selection import GroupKFold

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

from bigideas import build_silver_cgm, build_silver_meals  # noqa: E402
from bigideas.baseline import windows  # noqa: E402
from gummi_model import config as C  # noqa: E402
from gummi_model import evaluate as E  # noqa: E402
from gummi_model.train import build_samples, fit_horizons, predict_horizons  # noqa: E402

CANDIDATES = [120, 135, 150, 165, None]   # minutes after data_through; None = every horizon
HORIZONS = tuple(range(5, 181, 5))        # every 5-minute step out to the end of the 2-hour forecast


def cv_mae(samples, groups, cutoff, n_splits) -> float:
    C.MEAL_COL_RAMP_MIN.clear()
    if cutoff is not None:
        C.MEAL_COL_RAMP_MIN["carbs_big_g"] = (cutoff, cutoff + 5)
    ks = [h // C.STEP_MIN - 1 for h in HORIZONS]
    errs = {k: [] for k in ks}
    for tr, te in GroupKFold(n_splits=n_splits).split(np.zeros(len(samples)), groups=groups):
        m_tr = np.zeros(len(samples), bool); m_tr[tr] = True
        a, b = samples.subset(m_tr), samples.subset(~m_tr)
        models, _ = fit_horizons(a, "cgm_meals", ks)
        p = predict_horizons(models, b, "cgm_meals")
        for k in ks:
            e = np.abs(b.y[:, k] - p[:, k])
            errs[k].append(np.nanmean(e))
    return float(np.mean([np.mean(v) for v in errs.values()]))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(DATA / "raw" / "bigideas_1.1.3"))
    args = ap.parse_args()
    cgm = build_silver_cgm(args.raw)
    meals = build_silver_meals(args.raw)
    cgm = cgm[cgm.participant_id != "015"]
    _, _, groups = windows(cgm)
    folds = E.fold_map(groups)
    C.MEAL_COLS[:] = list(C.INPUT_MACROS) + ["carbs_big_g"]
    s = build_samples(cgm, meals)
    fold_of = np.array([folds[p] for p in s.pid])
    out = {"outer": {}, "inner_mae": {}}
    for f in sorted(set(folds.values())):
        tr = s.subset(fold_of != f)
        scores = {str(c): cv_mae(tr, tr.pid, c, 4) for c in CANDIDATES}
        best = min(scores, key=scores.get)
        out["outer"][f] = best
        out["inner_mae"][f] = {k: round(v, 3) for k, v in scores.items()}
        print(f"fold {f}: inner MAE {out['inner_mae'][f]} -> {best}")
    full = {str(c): cv_mae(s, np.array([folds[p] for p in s.pid]), c, 5) for c in CANDIDATES}
    out["shipped_scores"] = {k: round(v, 3) for k, v in full.items()}
    out["shipped"] = min(full, key=full.get)
    print("all participants:", out["shipped_scores"], "->", out["shipped"])
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
