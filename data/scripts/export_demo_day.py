"""Export one participant-day as plain CSVs for mocks and demo planning (reports/demo_day/).

Writes p<ID>_day<N>_cgm.csv (replay_cgm rows), p<ID>_day<N>_food_log.csv (item rows as logged, with the fat repair
from silver) and p<ID>_day<N>_meals.csv (replay_meals rows, what the replay releases). Meal ids match silver_meals.

    python data/scripts/export_demo_day.py --participant 012 --day 4
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

from bigideas.loaders import discover, load_food_log  # noqa: E402
from bigideas.silver import MEAL_GROUP_MIN, fix_fat_logged_as_calories  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(DATA / "raw" / "bigideas_1.1.3"))
    ap.add_argument("--local-out", default=str(DATA / "local_out"))
    ap.add_argument("--participant", default="012")
    ap.add_argument("--day", type=int, default=4)
    ap.add_argument("--out-dir", default=str(DATA / "reports" / "demo_day"))
    args = ap.parse_args()
    pid, day = args.participant, args.day
    lo, out = Path(args.local_out), Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    stem = f"p{pid}_day{day}"

    rc = pd.read_csv(lo / "replay_cgm.csv", dtype={"participant_id": str})
    rm = pd.read_csv(lo / "replay_meals.csv", dtype={"participant_id": str})
    c = rc[(rc.participant_id == pid) & (rc.day_index == day)].sort_values("minute_of_day")
    cgm = pd.DataFrame({"user_id": c.user_id, "day_index": c.day_index, "minute_of_day": c.minute_of_day,
                        "local_time": [f"{m // 60:02d}:{m % 60:02d}" for m in c.minute_of_day.astype(int)],
                        "glucose_mg_dl": c.glucose_mg_dl})
    cgm.to_csv(out / f"{stem}_cgm.csv", index=False)

    m = rm[(rm.participant_id == pid) & (rm.day_index == day)].sort_values("minute_of_day")
    m[["user_id", "meal_id", "day_index", "minute_of_day", "items", "carbs_g", "sugar_g", "fiber_g", "protein_g",
       "fat_g", "calories", "is_standard_breakfast"]].to_csv(out / f"{stem}_meals.csv", index=False)

    # item rows: the same sort, fat repair and 15-minute chaining as build_silver_meals, so meal ids line up
    food = fix_fat_logged_as_calories(load_food_log(discover(args.raw)[pid]["Food_Log"]))
    food = food.sort_values("eaten_at").reset_index(drop=True)
    gap = food["eaten_at"].diff().dt.total_seconds().div(60)
    occ = (gap.isna() | (gap > MEAL_GROUP_MIN)).cumsum()
    food["meal_id"] = [f"{pid}-{i:03d}" for i in occ]
    items = food[food.meal_id.isin(set(m.meal_id))].copy()
    mod = items.eaten_at.dt.hour * 60 + items.eaten_at.dt.minute
    log = pd.DataFrame({"meal_id": items.meal_id, "local_time": items.eaten_at.dt.strftime("%H:%M"),
                        "minute_of_day": mod, "logged_food": items.logged_food, "amount": items.amount,
                        "unit": items.unit, "carbs_g": items.total_carb, "sugar_g": items.sugar,
                        "protein_g": items.protein, "fat_g": items.total_fat,
                        "is_standard_breakfast": items.is_standard_breakfast})
    log.to_csv(out / f"{stem}_food_log.csv", index=False)

    n_meals_logged = log.meal_id.nunique()
    if n_meals_logged != len(m):
        raise SystemExit(f"meal ids do not line up: {n_meals_logged} in the food log, {len(m)} in replay_meals")
    print(f"{stem}: {len(cgm)} readings ({cgm.local_time.iloc[0]} to {cgm.local_time.iloc[-1]}, "
          f"{cgm.glucose_mg_dl.min():.0f} to {cgm.glucose_mg_dl.max():.0f} mg/dL), {len(log)} food items, "
          f"{len(m)} meals")
    return 0


if __name__ == "__main__":
    sys.exit(main())
