"""Walk effect with a source label, and the personal permutation test.

Literature effect: Buffey et al. 2022 (Sports Medicine 52:1765-1787) meta-analysis, light-intensity walking
versus prolonged sitting, postprandial glucose standardized mean difference d = -0.72 (95% CI -1.03 to -0.41).
Gummi converts d to mg/dL with the standard deviation of post-meal rises measured in BIG IDEAs
(meta["cohort"]["meal_rise_sd_mg_dl"]), for a walk of at least 10 minutes started after a meal, scaled down
linearly for shorter walks and never extrapolated above 10 minutes. This is a coaching prior, labeled
"literature" in the UI, until a person's own meals pass permutation_test (then "your data").
Caveat stated in reports/walk_effect.md: the meta-analysis pools sitting-interruption protocols, not a single
10-minute walk, and the conversion assumes the cohort's rise SD.
"""
from __future__ import annotations

import numpy as np

from . import config as C


def walk_effect(meta: dict, ctx, minutes: float, intensity: str) -> dict:
    personal = (getattr(ctx, "personal", None) or {}) if ctx is not None else {}
    pw = personal.get("walk_effect")
    if pw and pw.get("status") == "significant" and pw.get("drop_mg_dl") is not None:
        drop = float(pw["drop_mg_dl"]) * min(float(minutes) / C.WALK["reference_minutes"], 1.0)
        return {"forecast_peak_drop_mg_dl": round(max(drop, 0.0), 1), "effect_source": "your data",
                "basis": f"your meals: {pw.get('n_with')} with a walk after vs {pw.get('n_without')} without, "
                         f"p={pw.get('p_value')}"}
    if str(intensity).lower() == "sedentary" or minutes <= 0:
        return {"forecast_peak_drop_mg_dl": 0.0, "effect_source": "literature", "citation": C.WALK["citation"],
                "basis": "no walking detected"}
    sd = float((meta or {}).get("cohort", {}).get("meal_rise_sd_mg_dl") or 0.0)
    drop = C.WALK["effect_size_d"] * sd * min(float(minutes) / C.WALK["reference_minutes"], 1.0)
    return {"forecast_peak_drop_mg_dl": round(drop, 1), "effect_source": "literature",
            "citation": C.WALK["citation"],
            "basis": f"d = {C.WALK['effect_size_d']} x SD of post-meal rise in BIG IDEAs ({sd:.1f} mg/dL)"}


def permutation_test(rises_with_walk, rises_without_walk, n_perm: int = C.PERMUTATION_N, seed: int = 0) -> dict:
    """One-sided test that walking after a meal lowers the post-meal rise, on one person's meals."""
    a = np.asarray([x for x in rises_with_walk if x is not None and not np.isnan(x)], dtype=float)
    b = np.asarray([x for x in rises_without_walk if x is not None and not np.isnan(x)], dtype=float)
    out = {"n_with": int(len(a)), "n_without": int(len(b))}
    if len(a) < C.PERMUTATION_MIN_PER_GROUP or len(b) < C.PERMUTATION_MIN_PER_GROUP:
        return {**out, "status": "not enough data yet", "drop_mg_dl": None, "p_value": None}
    observed = float(b.mean() - a.mean())            # positive = walks lowered the rise
    pooled = np.concatenate([a, b])
    rng = np.random.default_rng(seed)
    count = 0
    for _ in range(n_perm):
        rng.shuffle(pooled)
        if pooled[len(a):].mean() - pooled[:len(a)].mean() >= observed:
            count += 1
    p = (count + 1) / (n_perm + 1)
    status = "significant" if (p < C.PERMUTATION_ALPHA and observed > 0) else "not significant"
    return {**out, "status": status, "drop_mg_dl": round(observed, 1), "p_value": round(p, 4)}
