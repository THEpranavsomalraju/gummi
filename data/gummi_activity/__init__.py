"""Walk intensity from step cadence and walk summaries (CONTRACT.md section 8).

    from gummi_activity import intensity_from_cadence, summarize_walk

Cadence bands: Tudor-Locke C, Aguiar EJ, Han H, et al. (2019). Walking cadence (steps/min) and intensity in
21-40 year olds: CADENCE-adults. International Journal of Behavioral Nutrition and Physical Activity 16:8.
doi:10.1186/s12966-019-0769-6. Heuristic thresholds: 100 steps/min ~ 3 METs (moderate), 110 ~ 4, 120 ~ 5,
130 ~ 6 METs (vigorous); roughly 1 MET per 10 steps/min in that range.
Gummi's labels: 0 steps/min "sedentary"; 1-99 "light" (ASSUMED: any walking below the published moderate
threshold); 100-129 "moderate"; 130+ "vigorous". METs are only estimated at 100+ steps/min, where the paper
supports it. Caveat: the bands come from adults aged 21-40; Gummi's users are older (D-19 may validate on IMU50).
"""
from __future__ import annotations

from datetime import datetime, timezone

import pandas as pd

CITATION = ("Tudor-Locke C, et al. (2019). Walking cadence (steps/min) and intensity in 21-40 year olds: "
            "CADENCE-adults. Int J Behav Nutr Phys Act 16:8. doi:10.1186/s12966-019-0769-6")
MODERATE_SPM = 100
VIGOROUS_SPM = 130

__all__ = ["intensity_from_cadence", "summarize_walk", "CITATION"]


def intensity_from_cadence(cadence_spm: float | None) -> dict:
    """{"intensity", "mets_estimate", "source"} for a cadence in steps per minute."""
    if cadence_spm is None or pd.isna(cadence_spm) or cadence_spm <= 0:
        return {"intensity": "sedentary", "mets_estimate": None, "source": CITATION}
    c = float(cadence_spm)
    if c >= VIGOROUS_SPM:
        label = "vigorous"
    elif c >= MODERATE_SPM:
        label = "moderate"
    else:
        label = "light"
    mets = round(3.0 + (c - MODERATE_SPM) / 10.0, 1) if c >= MODERATE_SPM else None
    return {"intensity": label, "mets_estimate": mets, "source": CITATION}


def _utc(ts) -> pd.Timestamp:
    t = pd.Timestamp(ts)
    return t.tz_localize("UTC") if t.tzinfo is None else t.tz_convert("UTC")


def summarize_walk(step_samples, started_at=None, ended_at=None, walk_effect: dict | None = None) -> dict:
    """WalkSummary fields from step samples.

    step_samples: list of {"value": steps, "start": ..., "end": ...} (the /vitals steps samples) or a
    DataFrame with those columns. started_at/ended_at bound the walk (default: span of the samples).
    walk_effect: optional output of GlucoseModel.walk_effect to fill forecast_peak_drop_mg_dl and effect_source.
    Cadence = steps / walking minutes (minutes covered by samples with steps > 0).
    """
    df = pd.DataFrame(step_samples)
    if df.empty:
        raise ValueError("no step samples")
    df["start"] = df["start"].map(_utc)
    df["end"] = df["end"].map(_utc)
    s = _utc(started_at) if started_at is not None else df["start"].min()
    e = _utc(ended_at) if ended_at is not None else df["end"].max()
    df = df[(df["end"] > s) & (df["start"] < e)].copy()
    # count only the part of each sample inside the walk window
    span = (df["end"] - df["start"]).dt.total_seconds().clip(lower=1)
    inside = (df["end"].clip(upper=e) - df["start"].clip(lower=s)).dt.total_seconds().clip(lower=0)
    df["steps_in"] = df["value"].astype(float) * inside / span
    df["minutes_in"] = inside / 60.0
    steps = float(df["steps_in"].sum())
    walking_minutes = float(df.loc[df["steps_in"] > 0, "minutes_in"].sum())
    minutes = (e - s).total_seconds() / 60.0
    cadence = steps / walking_minutes if walking_minutes > 0 else 0.0
    inten = intensity_from_cadence(cadence)
    return {
        "started_at": s.isoformat(),
        "ended_at": e.isoformat(),
        "minutes": int(round(minutes)),
        "steps": int(round(steps)),
        "cadence_spm": int(round(cadence)),
        "intensity": inten["intensity"],
        "forecast_peak_drop_mg_dl": (walk_effect or {}).get("forecast_peak_drop_mg_dl"),
        "effect_source": (walk_effect or {}).get("effect_source"),
    }
