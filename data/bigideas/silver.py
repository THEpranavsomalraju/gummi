"""Silver-layer builders: CGM master clock with islands, meal occasions, motion per CGM slot."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from .loaders import MACROS, discover, load_dexcom, load_food_log

GAP_MIN = 15          # new island when the gap to the previous reading exceeds this (PhysioFusion)
MEAL_GROUP_MIN = 15   # food log rows within this many minutes of the previous row form one occasion


def segment_islands(cgm: pd.DataFrame, gap_min: float = GAP_MIN) -> pd.DataFrame:
    """Add an integer 'island' column: contiguous runs without gaps > gap_min (sorted by ts)."""
    cgm = cgm.sort_values("ts").reset_index(drop=True).copy()
    dt = cgm["ts"].diff().dt.total_seconds().div(60)
    cgm["gap_before_min"] = dt
    cgm["island"] = (dt > gap_min).cumsum().astype(int)
    return cgm


def build_silver_cgm(root: str | Path, participants: list[str] | None = None) -> pd.DataFrame:
    """silver_cgm_5min: participant_id, ts, glucose, glucose_flag, island, gap_before_min, day_index, minute_of_day."""
    files = discover(root)
    parts = []
    for pid in sorted(files):
        if participants and pid not in participants:
            continue
        if "Dexcom" not in files[pid]:
            continue
        cgm = segment_islands(load_dexcom(files[pid]["Dexcom"]))
        cgm.insert(0, "participant_id", pid)
        first_day = cgm["ts"].dt.normalize().min()
        cgm["day_index"] = ((cgm["ts"].dt.normalize() - first_day).dt.days + 1).astype(int)
        cgm["minute_of_day"] = cgm["ts"].dt.hour * 60 + cgm["ts"].dt.minute
        parts.append(cgm)
    if not parts:
        raise FileNotFoundError(f"no Dexcom files under {root}")
    return pd.concat(parts, ignore_index=True)


def group_meals(food: pd.DataFrame, window_min: float = MEAL_GROUP_MIN) -> pd.DataFrame:
    """Collapse item rows into eating occasions. Chained: a row within window_min of the previous row joins it."""
    food = food.sort_values("eaten_at").reset_index(drop=True)
    gap = food["eaten_at"].diff().dt.total_seconds().div(60)
    occ = (gap.isna() | (gap > window_min)).cumsum()
    agg = {m: "sum" for m in MACROS}
    g = food.groupby(occ)
    meals = g.agg({"eaten_at": "min", **agg})
    meals["items"] = g["logged_food"].apply(lambda s: " | ".join(s))
    meals["n_items"] = g.size()
    meals["is_standard_breakfast"] = g["is_standard_breakfast"].any()
    # any macro entirely missing for every item stays NaN instead of a misleading 0
    for m in MACROS:
        all_nan = g[m].apply(lambda s: s.isna().all())
        meals.loc[all_nan, m] = np.nan
    return meals.reset_index(drop=True)


def fix_fat_logged_as_calories(food: pd.DataFrame) -> pd.DataFrame:
    """Repair food-log rows where the fat column repeats the calories (e.g. 012 almonds: fat 255 g, 255 kcal).

    Such a row claims 9 x fat kcal from fat alone, far above its own calories. Fat is re-derived from the energy left
    after carbs and protein: (calories - 4 carbs - 4 protein) / 9, at least 0. Two rows in BIG IDEAs 1.1.3 (010 bacon,
    012 almonds). Rows without calories are left alone.
    """
    f = food.copy()
    cal = pd.to_numeric(f["calorie"], errors="coerce")
    fat = pd.to_numeric(f["total_fat"], errors="coerce")
    bad = (cal > 20) & (fat.round(1) == cal.round(1)) & (9 * fat > cal + 50)
    if bad.any():
        rest = cal - 4 * pd.to_numeric(f["total_carb"], errors="coerce").fillna(0) \
            - 4 * pd.to_numeric(f["protein"], errors="coerce").fillna(0)
        f.loc[bad, "total_fat"] = (rest[bad] / 9).clip(lower=0).round(1)
    return f


def build_silver_meals(root: str | Path, participants: list[str] | None = None) -> pd.DataFrame:
    """silver_meals: participant_id, meal_id, eaten_at, macro totals, items, is_standard_breakfast, meal_slot."""
    files = discover(root)
    parts = []
    for pid in sorted(files):
        if participants and pid not in participants:
            continue
        if "Food_Log" not in files[pid]:
            continue
        meals = group_meals(fix_fat_logged_as_calories(load_food_log(files[pid]["Food_Log"])))
        meals.insert(0, "participant_id", pid)
        meals.insert(1, "meal_id", [f"{pid}-{i + 1:03d}" for i in range(len(meals))])
        hour = meals["eaten_at"].dt.hour
        meals["meal_slot"] = np.select(
            [hour < 11, hour < 16, hour < 22], ["breakfast", "lunch", "dinner"], default="late"
        )
        parts.append(meals)
    out = pd.concat(parts, ignore_index=True)
    return out.rename(columns={
        "calorie": "calories", "total_carb": "carbs_g", "dietary_fiber": "fiber_g",
        "sugar": "sugar_g", "protein": "protein_g", "total_fat": "fat_g",
    })


def acc_to_minutes(acc_path: str | Path, chunksize: int = 2_000_000) -> pd.DataFrame:
    """Stream a 32 Hz E4 ACC file into per-minute motion features without loading it whole.

    Units: raw E4 ACC is in 1/64 g. Detected from the median magnitude (~64 at rest) and converted to g.
    Returns minute, n, vm_mean, vm_sd, vm_max, enmo_mean (milli-g).
    """
    sums = []
    scale = None
    for chunk in pd.read_csv(acc_path, chunksize=chunksize):
        chunk.columns = [c.strip() for c in chunk.columns]
        t = pd.to_datetime(chunk["datetime"])
        xyz = chunk[["acc_x", "acc_y", "acc_z"]].to_numpy(dtype=float)
        vm = np.sqrt((xyz ** 2).sum(axis=1))
        if scale is None:
            scale = 64.0 if np.nanmedian(vm) > 8 else 1.0
        vm = vm / scale
        enmo = np.maximum(vm - 1.0, 0.0) * 1000.0
        d = pd.DataFrame({"minute": t.dt.floor("min"), "vm": vm, "vm2": vm ** 2, "enmo": enmo})
        sums.append(d.groupby("minute").agg(n=("vm", "size"), vm_sum=("vm", "sum"), vm2_sum=("vm2", "sum"),
                                            vm_max=("vm", "max"), enmo_sum=("enmo", "sum")))
    s = pd.concat(sums).groupby(level=0).agg({"n": "sum", "vm_sum": "sum", "vm2_sum": "sum",
                                              "vm_max": "max", "enmo_sum": "sum"})
    out = pd.DataFrame(index=s.index)
    out["n"] = s["n"]
    out["vm_mean"] = s["vm_sum"] / s["n"]
    out["vm_sd"] = np.sqrt(np.maximum(s["vm2_sum"] / s["n"] - out["vm_mean"] ** 2, 0))
    out["vm_max"] = s["vm_max"]
    out["enmo_mean"] = s["enmo_sum"] / s["n"]
    return out.reset_index()


def minutes_to_cgm_slots(minutes: pd.DataFrame, cgm_ts: pd.Series, value_cols: list[str],
                         window_min: int = 5, min_minutes: int = 3) -> pd.DataFrame:
    """For each CGM time t, average per-minute rows in (t-5min, t]. NaN when fewer than min_minutes."""
    m = minutes.set_index("minute").sort_index()
    rows = []
    for t in pd.to_datetime(cgm_ts):
        sl = m.loc[(m.index > t - pd.Timedelta(minutes=window_min)) & (m.index <= t), value_cols]
        rows.append(sl.mean() if len(sl) >= min_minutes else pd.Series(np.nan, index=value_cols))
    out = pd.DataFrame(rows).reset_index(drop=True)
    out.insert(0, "ts", pd.to_datetime(cgm_ts).reset_index(drop=True))
    return out


def completeness_report(silver_cgm: pd.DataFrame) -> pd.DataFrame:
    """Per participant: days, readings, glucose stats, biggest gap, completeness vs a perfect 5-min record."""
    rows = []
    for pid, g in silver_cgm.groupby("participant_id"):
        span_min = (g["ts"].max() - g["ts"].min()).total_seconds() / 60
        expected = span_min / 5 + 1
        rows.append({
            "participant_id": pid,
            "days": int(g["day_index"].max()),
            "readings": len(g),
            "glucose_mean": round(g["glucose"].mean(), 1),
            "glucose_sd": round(g["glucose"].std(), 1),
            "glucose_min": g["glucose"].min(),
            "glucose_max": g["glucose"].max(),
            "biggest_gap_min": round(g["gap_before_min"].max(), 0),
            "islands": g["island"].nunique(),
            "low_high_flags": int(g["glucose_flag"].notna().sum()),
            "completeness": round(len(g) / expected, 3),
        })
    return pd.DataFrame(rows)
