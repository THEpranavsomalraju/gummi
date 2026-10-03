"""Replay tables: replay_cgm and replay_meals with times relative to each participant's day start.

t_offset_min = minutes since local midnight of that participant's first recorded day. The Backend's
replay producer maps (day_index, minute_of_day) onto today's replay clock and delays CGM by 60 minutes.
"""
from __future__ import annotations

import pandas as pd


def _offsets(ts: pd.Series, day0: pd.Timestamp) -> pd.Series:
    return ((ts - day0).dt.total_seconds() / 60.0).round(2)


def replay_tables(silver_cgm: pd.DataFrame, silver_meals: pd.DataFrame, participants: list[str]):
    cg, ml = [], []
    for pid in participants:
        g = silver_cgm[silver_cgm["participant_id"] == pid].sort_values("ts")
        if g.empty:
            continue
        day0 = g["ts"].dt.normalize().min()
        cg.append(pd.DataFrame({
            "user_id": f"p_{pid}", "participant_id": pid, "day_index": g["day_index"].to_numpy(),
            "minute_of_day": g["minute_of_day"].to_numpy(), "t_offset_min": _offsets(g["ts"], day0).to_numpy(),
            "glucose_mg_dl": g["glucose"].round(1).to_numpy(), "island": g["island"].to_numpy(),
        }))
        m = silver_meals[silver_meals["participant_id"] == pid].sort_values("eaten_at")
        if len(m):
            ml.append(pd.DataFrame({
                "user_id": f"p_{pid}", "participant_id": pid, "meal_id": m["meal_id"].to_numpy(),
                "day_index": ((m["eaten_at"].dt.normalize() - day0).dt.days + 1).to_numpy(),
                "minute_of_day": (m["eaten_at"].dt.hour * 60 + m["eaten_at"].dt.minute).to_numpy(),
                "t_offset_min": _offsets(m["eaten_at"], day0).to_numpy(),
                "items": m["items"].to_numpy(), "carbs_g": m["carbs_g"].to_numpy(), "sugar_g": m["sugar_g"].to_numpy(),
                "fiber_g": m["fiber_g"].to_numpy(), "protein_g": m["protein_g"].to_numpy(), "fat_g": m["fat_g"].to_numpy(),
                "calories": m["calories"].to_numpy(), "is_standard_breakfast": m["is_standard_breakfast"].to_numpy(),
            }))
    return pd.concat(cg, ignore_index=True), pd.concat(ml, ignore_index=True)
