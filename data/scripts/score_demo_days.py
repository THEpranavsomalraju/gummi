"""Score every qualifying demo day (reports/demo_day_candidates.csv) with the shipped model, out of sample.

For each participant-day, make_test_events.py replays 19 hours from an hour before breakfast with model.for_user (the
fold model that never saw that person) and grades every meal and hourly nowcast. This script summarizes those grades:
meals where Gummi's curve beats CGM-only's, mean meal-curve error for Gummi, CGM-only and last value, mean error over
all grades, and mean peak error at meal time. Used to pick D-15 (reports/demo_day_scores.md).

    python data/scripts/score_demo_days.py --local-out data/local_out --work /tmp/demo_days
"""
from __future__ import annotations

import argparse
import glob
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pandas as pd

DATA = Path(__file__).resolve().parents[1]


def score(out: Path) -> dict | None:
    preds, grades = {}, []
    for f in sorted(glob.glob(str(out / "*.jsonl"))):
        for line in open(f):
            e = json.loads(line)
            if e["kind"] == "prediction" and e["payload"]["kind"] == "meal":
                preds[e["payload"]["prediction_id"]] = e["payload"]
            elif e["kind"] == "grade":
                grades.append(e["payload"])
    g = pd.DataFrame(grades)
    if g.empty or not (g.kind == "meal").any():
        return None
    mg = g[g.kind == "meal"]
    gpk = pd.Series([preds[p]["predicted_peak_mg_dl"] for p in mg.prediction_id], index=mg.index)
    cpk = pd.Series([preds[p]["cgm_only_peak_mg_dl"] for p in mg.prediction_id], index=mg.index)
    return {
        "meals_graded": len(mg),
        "meals_gummi_beats_cgm_only": int(mg.gummi_beats_cgm_only.sum()),
        "meal_curve_gummi": round(mg.gummi_mae_mg_dl.mean(), 1),
        "meal_curve_cgm_only": round(mg.cgm_only_mae_mg_dl.mean(), 1),
        "meal_curve_last_value": round(mg.last_value_mae_mg_dl.mean(), 1),
        "all_grades": len(g),
        "all_gummi_beats_cgm_only": int(g.gummi_beats_cgm_only.sum()),
        "all_gummi": round(g.gummi_mae_mg_dl.mean(), 1),
        "all_cgm_only": round(g.cgm_only_mae_mg_dl.mean(), 1),
        "peak_error_gummi": round((gpk - mg.actual_peak_mg_dl).abs().mean(), 1),
        "peak_error_cgm_only": round((cpk - mg.actual_peak_mg_dl).abs().mean(), 1),
        "first_meal_message": mg.message.iloc[0],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--local-out", default=str(DATA / "local_out"))
    ap.add_argument("--candidates", default=str(DATA / "reports" / "demo_day_candidates.csv"))
    ap.add_argument("--work", default=str(DATA / "local_out" / "demo_day_scores"))
    ap.add_argument("--out", default=str(DATA / "reports" / "demo_day_scores.csv"))
    args = ap.parse_args()
    cand = pd.read_csv(args.candidates)
    rows = []
    for _, r in cand[cand.qualifies].iterrows():
        pid, day = f"{int(r.participant):03d}", int(r.replay_day)
        out = Path(args.work) / f"{pid}_day{day}"
        shutil.rmtree(out, ignore_errors=True)
        cmd = [sys.executable, str(DATA / "scripts" / "make_test_events.py"), "--local-out", args.local_out,
               "--participants", pid, "--replay-day", str(day), "--hours", "19", "--out", str(out)]
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode:
            print(f"{pid} day {day}: failed\n{p.stderr[-400:]}", file=sys.stderr)
            continue
        s = score(out)
        if s:
            rows.append({"participant": pid, "replay_day": day, **s})
            print(f"{pid} day {day}: {s['meals_gummi_beats_cgm_only']}/{s['meals_graded']} meals, curve "
                  f"{s['meal_curve_gummi']} vs {s['meal_curve_cgm_only']}", flush=True)
    res = pd.DataFrame(rows)
    res["meal_curve_edge"] = (res.meal_curve_cgm_only - res.meal_curve_gummi).round(1)
    res = res.sort_values("meal_curve_edge", ascending=False)
    res.to_csv(args.out, index=False)
    print(res.drop(columns="first_meal_message").to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
