"""Rank replay days for the demo (decision D-15) from run_local_pipeline.py outputs.

    python data\\scripts\\demo_day_candidates.py

A day qualifies with CGM coverage of at least 97% from 06:00 to 22:00, a standardized-breakfast rise of at least
40 mg/dL, a later meal (11:00 or after), and at least one meal whose participant-grouped predicted peak reaches the
140 mg/dL high line (the walk nudge in the demo script). 015 is excluded (D-20). Writes reports/demo_day_candidates.csv.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

DATA = Path(__file__).resolve().parents[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--local-out", default=str(DATA / "local_out"))
    ap.add_argument("--out", default=str(DATA / "reports" / "demo_day_candidates.csv"))
    ap.add_argument("--high-line", type=float, default=140.0)
    args = ap.parse_args()
    lo = Path(args.local_out)
    rc = pd.read_csv(lo / "replay_cgm.csv", dtype={"participant_id": str})
    rm = pd.read_csv(lo / "replay_meals.csv", dtype={"participant_id": str})
    mp = pd.read_csv(lo / "meal_predictions.csv", dtype={"participant_id": str})
    mr = pd.read_csv(lo / "meal_responses.csv", dtype={"participant_id": str})
    mp = mp[mp["model"] == "gummi_cgm_meals"]
    rows = []
    for (pid, day), g in rc[~rc["excluded_from_training"]].groupby(["participant_id", "day_index"]):
        slots = g[(g["minute_of_day"] >= 360) & (g["minute_of_day"] < 1320)]
        meals = rm[(rm["participant_id"] == pid) & (rm["day_index"] == day)]
        if not len(meals):
            continue
        ids = set(meals["meal_id"])
        bf = mr[mr["meal_id"].isin(ids) & mr["is_standard_breakfast"]]
        preds = mp[mp["meal_id"].isin(ids)]
        rows.append({
            "participant": pid, "replay_day": int(day), "coverage_06_22": round(len(slots) / 192, 3),
            "meals": len(meals), "later_meals": int((meals["minute_of_day"] >= 660).sum()),
            "breakfast_rise_mg_dl": float(bf["rise_mg_dl"].max()) if bf["rise_mg_dl"].notna().any() else np.nan,
            "forecast_peaks_at_high_line": int((preds["predicted_peak"] >= args.high_line).sum()),
            "actual_peaks_at_high_line": int((preds["actual_peak"] >= args.high_line).sum()),
            "graded_meals": len(preds),
            "gummi_curve_mae": round(float(preds["curve_mae"].mean()), 1) if len(preds) else np.nan,
            "last_value_curve_mae": round(float(preds["last_value_curve_mae"].mean()), 1) if len(preds) else np.nan,
            "gummi_peak_error": round(float(preds["peak_abs_err"].mean()), 1) if len(preds) else np.nan,
        })
    d = pd.DataFrame(rows)
    d["qualifies"] = ((d["coverage_06_22"] >= 0.97) & (d["breakfast_rise_mg_dl"] >= 40) & (d["later_meals"] >= 1)
                      & (d["forecast_peaks_at_high_line"] >= 1))
    d = d.sort_values(["qualifies", "forecast_peaks_at_high_line", "breakfast_rise_mg_dl"], ascending=False)
    d.to_csv(args.out, index=False)
    print(f"{int(d['qualifies'].sum())} of {len(d)} participant-days qualify -> {args.out}")
    print(d[d["qualifies"]].head(10).to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
