"""GET /day: the day's synopsis for the dashboard tab (CONTRACT 1.6). Computed from hot state, no LLM, so it loads in
milliseconds. While acting as a participant the day is the replayed day mapped to today (D-45)."""
from datetime import date as Date

import numpy as np
import pandas as pd
from fastapi import APIRouter, Depends

from .. import config
from ..auth import user_id
from ..engine.engine import engine
from ..state.hot_store import store
from ..state.view import build_state
from ..stream.producer import clock
from ..util import TZ, iso, r1

router = APIRouter()


def _hm(t) -> str:
    return pd.Timestamp(t).tz_convert(TZ).strftime("%-I:%M %p")


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return r1(float(np.mean(xs))) if xs else None


@router.get("/day")
async def day(uid: str = Depends(user_id), date: str | None = None):
    u = store.get(uid)
    s = engine.subjects.get(u.following) if u.following else None
    st = build_state(uid)
    now = clock.replay_to_wall(clock.now()) if s is not None and clock.now() is not None else pd.Timestamp.now(tz=TZ)
    day_ = date or pd.Timestamp(now).tz_convert(TZ).date().isoformat()
    on_day = lambda t: pd.Timestamp(t).tz_convert(TZ).date().isoformat() == day_  # noqa: E731
    lo, hi = u.profile["low_line_mg_dl"], u.profile["high_line_mg_dl"]
    out = {"date": day_, "participant": s.pid if s else None, "data_status": st["data_status"],
           "glucose": None, "hourly": [], "meals": {"count": 0, "carbs_g": 0.0, "biggest": None},
           "activity": {"steps": u.steps, "walks": len(u.walks), "walk_minutes": int(sum(w["minutes"] for w in u.walks))},
           "predictions": {"made": 0, "graded": 0, "gummi_mae_mg_dl": None, "cgm_only_mae_mg_dl": None,
                           "last_value_mae_mg_dl": None, "beat_cgm_only_pct": None},
           "best_call": None, "biggest_spike": None, "highlights": [], "recap": None}
    if s is not None:
        n = min(len(s.conf_t), len(s.conf_v))
        pts = [(t, v) for t, v in zip(s.conf_t[:n], s.conf_v[:n]) if on_day(t)]
        if pts:
            vals = [v for _, v in pts]
            t_peak, v_peak = max(pts, key=lambda p: p[1])
            t_low, v_low = min(pts, key=lambda p: p[1])
            out["glucose"] = {"readings": len(vals), "time_in_range_pct": r1(100 * sum(lo <= v <= hi for v in vals) / len(vals)),
                              "average_mg_dl": r1(float(np.mean(vals))), "peak": {"mg_dl": v_peak, "at": iso(t_peak)},
                              "low": {"mg_dl": v_low, "at": iso(t_low)}}
            by_hour: dict[int, list] = {}
            for t, v in pts:
                by_hour.setdefault(pd.Timestamp(t).tz_convert(TZ).hour, []).append(v)
            out["hourly"] = [{"hour": h, "avg_mg_dl": r1(float(np.mean(v))), "min_mg_dl": min(v), "max_mg_dl": max(v)}
                             for h, v in sorted(by_hour.items())]
        meals = [m for m in list(s.meals) + list(u.meals) if on_day(m["eaten_at"])]
        if meals:
            big = max(meals, key=lambda m: m["totals"]["carbs_g"])
            out["meals"] = {"count": len(meals), "carbs_g": r1(sum(m["totals"]["carbs_g"] for m in meals)),
                            "biggest": {"food": big["items"][0]["name"], "carbs_g": big["totals"]["carbs_g"], "at": big["eaten_at"]}}
        preds = [p for p in list(s.predictions.values()) if on_day(p["made_at"]) and not p.get("about", "").startswith("simulated")]
        grades = [g for g in list(s.grades) if on_day(g["graded_at"])]
        beat = [g["gummi_beats_cgm_only"] for g in grades if g["gummi_beats_cgm_only"] is not None]
        out["predictions"] = {"made": len(preds), "graded": len(grades),
                              "gummi_mae_mg_dl": _mean(g["gummi_mae_mg_dl"] for g in grades),
                              "cgm_only_mae_mg_dl": _mean(g["cgm_only_mae_mg_dl"] for g in grades),
                              "last_value_mae_mg_dl": _mean(g["last_value_mae_mg_dl"] for g in grades),
                              "beat_cgm_only_pct": r1(100 * sum(beat) / len(beat)) if beat else None}
        meal_grades = [g for g in grades if g["kind"] == "meal"]
        if meal_grades:
            best = min(meal_grades, key=lambda g: g["gummi_peak_error_mg_dl"])
            out["best_call"] = {"about": s.predictions.get(best["prediction_id"], {}).get("about"), "message": best["message"],
                                "gummi_peak_error_mg_dl": best["gummi_peak_error_mg_dl"]}
        if pts and meals:
            before = [m for m in meals if pd.Timestamp(m["eaten_at"]) <= t_peak]
            out["biggest_spike"] = {"peak_mg_dl": v_peak, "at": iso(t_peak),
                                    "after_meal": before[-1]["items"][0]["name"] if before else None}
        # first-person highlights, all numbers from the data above
        g = out["glucose"]
        if g:
            out["highlights"].append(f"You were in range {g['time_in_range_pct']:.0f}% of the day, averaging about {g['average_mg_dl']:.0f} mg/dL.")
        if out["biggest_spike"] and out["biggest_spike"]["after_meal"]:
            b = out["biggest_spike"]
            out["highlights"].append(f"Your biggest rise peaked at {b['peak_mg_dl']:.0f} mg/dL at {_hm(b['at'])}, after {b['after_meal'].lower()}.")
        p = out["predictions"]
        if p["graded"]:
            out["highlights"].append(f"I graded {p['graded']} predictions: off by {p['gummi_mae_mg_dl']} mg/dL on average, "
                                     f"against {p['cgm_only_mae_mg_dl']} for CGM-only and {p['last_value_mae_mg_dl']} for last value.")
        if u.walks:
            out["highlights"].append(f"{len(u.walks)} walk{'s' if len(u.walks) != 1 else ''}, {out['activity']['walk_minutes']} minutes. Nice.")
    recap = [c for c in u.cards if c["type"] == "evening_recap" and c["created_at"][:10] == day_]
    out["recap"] = recap[-1] if recap else None
    return out


__all__ = ["router", "Date", "config"]
