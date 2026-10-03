"""Phase 1 exploration: post-meal rises, standardized-breakfast responses, cohort statistics."""
from __future__ import annotations

import numpy as np
import pandas as pd

PRE_MIN = 30        # baseline window before eating
PEAK_MIN = 150      # look for the peak within this many minutes after eating
OVERLAP_MIN = 120   # another meal inside this window after eating makes the rise "overlapped"


def meal_responses(silver_cgm: pd.DataFrame, silver_meals: pd.DataFrame) -> pd.DataFrame:
    """One row per meal: pre-meal baseline (median), peak, rise, time to peak, coverage, overlap flag."""
    rows = []
    for pid, meals in silver_meals.groupby("participant_id"):
        g = silver_cgm[silver_cgm["participant_id"] == pid].sort_values("ts")
        ts, v = g["ts"].to_numpy(), g["glucose"].to_numpy(dtype=float)
        eaten_all = meals["eaten_at"].sort_values().to_numpy()
        for _, m in meals.iterrows():
            e = np.datetime64(m["eaten_at"])
            pre = v[(ts >= e - np.timedelta64(PRE_MIN, "m")) & (ts <= e)]
            win_mask = (ts > e) & (ts <= e + np.timedelta64(PEAK_MIN, "m"))
            post, post_t = v[win_mask], ts[win_mask]
            nxt = eaten_all[(eaten_all > e) & (eaten_all <= e + np.timedelta64(OVERLAP_MIN, "m"))]
            ok = len(pre) >= 4 and len(post) >= int(0.8 * PEAK_MIN / 5)
            base = float(np.median(pre)) if len(pre) else np.nan
            peak = float(post.max()) if len(post) else np.nan
            ttp = float((post_t[post.argmax()] - e) / np.timedelta64(1, "m")) if len(post) else np.nan
            rows.append({
                "participant_id": pid, "meal_id": m["meal_id"], "eaten_at": m["eaten_at"],
                "carbs_g": m["carbs_g"], "sugar_g": m.get("sugar_g"), "is_standard_breakfast": bool(m["is_standard_breakfast"]),
                "meal_slot": m.get("meal_slot"), "baseline_mg_dl": base, "peak_mg_dl": peak,
                "rise_mg_dl": peak - base if ok else np.nan, "time_to_peak_min": ttp if ok else np.nan,
                "covered": ok, "overlapped": len(nxt) > 0,
            })
    return pd.DataFrame(rows)


def breakfast_response(resp: pd.DataFrame) -> pd.DataFrame:
    """Per participant: standardized-breakfast rises (gummi_ml.breakfast_response)."""
    sb = resp[resp["is_standard_breakfast"] & resp["covered"]].copy()
    sb["rise_per_g"] = sb["rise_mg_dl"] / sb["carbs_g"]
    out = sb.groupby("participant_id").agg(
        n=("meal_id", "count"), carbs_g_mean=("carbs_g", "mean"), rise_mean_mg_dl=("rise_mg_dl", "mean"),
        rise_sd_mg_dl=("rise_mg_dl", "std"), rise_min_mg_dl=("rise_mg_dl", "min"), rise_max_mg_dl=("rise_mg_dl", "max"),
        time_to_peak_min=("time_to_peak_min", "median"), rise_per_g=("rise_per_g", "median"),
        overlapped=("overlapped", "sum")).reset_index()
    return out.round(2)


def cohort_stats(resp: pd.DataFrame, bf: pd.DataFrame) -> dict:
    clean = resp[resp["covered"] & ~resp["overlapped"] & (resp["carbs_g"] >= 15)]
    pooled = resp[resp["covered"]]
    rho = pooled[["carbs_g", "rise_mg_dl"]].corr(method="spearman").iloc[0, 1] if len(pooled) > 5 else np.nan
    return {
        "meals_total": int(len(resp)),
        "meals_covered": int(resp["covered"].sum()),
        "meal_rise_sd_mg_dl": round(float(clean["rise_mg_dl"].std()), 2),
        "meal_rise_median_mg_dl": round(float(clean["rise_mg_dl"].median()), 2),
        "meal_rise_n": int(len(clean)),
        "rise_vs_carbs_spearman": round(float(rho), 3),
        "breakfast_rise_per_g_median": round(float(bf["rise_per_g"].median()), 3) if len(bf) else None,
        "breakfast_participants": int(len(bf)),
    }


def rise_vs_carbs_by_person(resp: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for pid, g in resp[resp["covered"]].groupby("participant_id"):
        if len(g) < 5:
            continue
        rho = g[["carbs_g", "rise_mg_dl"]].corr(method="spearman").iloc[0, 1]
        slope = np.polyfit(g["carbs_g"], g["rise_mg_dl"], 1)[0] if g["carbs_g"].nunique() > 1 else np.nan
        rows.append({"participant_id": pid, "meals": len(g), "spearman": round(float(rho), 2),
                     "mg_dl_per_10g_carbs": round(float(slope * 10), 2)})
    return pd.DataFrame(rows)
