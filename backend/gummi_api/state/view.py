"""Builds the contract State and FleetEntry objects from the engine and the per-teammate store, from memory only."""
import time
from datetime import datetime, timedelta

import numpy as np

from .. import config
from ..engine.engine import engine
from ..engine.gold import gold
from ..stream.producer import clock
from ..util import TZ, iso, r1
from .hot_store import dexcom_status, store

VIEW_KEYS = ("glucose_mg_dl", "band_low_mg_dl", "band_high_mg_dl", "trend", "as_of", "minutes_since_confirmed", "confidence")
_cache: dict = {}


def stream_status() -> dict:
    return clock.status(pipeline_lag_seconds=gold.pipeline_lag_seconds)


def subject_view(pid: str) -> dict | None:
    """Confirmed, estimate, forecast and GummiView for a replay participant at the replay clock, cached per second."""
    s = engine.subjects.get(pid)
    now_r = clock.now()
    if s is None or now_r is None or len(s.conf_t) < 3:
        return None
    key = (s.version, int(now_r * 4))
    hit = _cache.get(pid)
    if hit and hit[0] == key:
        return hit[1]
    now = clock.replay_to_wall(now_r)
    ctx = engine.ctx(s)
    est = s.model.estimate_gap(ctx, now)
    fc = s.model.forecast(ctx, now, 120)
    view = {k: v for k, v in s.model.gummi_view(ctx, now).items() if k in VIEW_KEYS}
    since = now - timedelta(hours=6)
    n = min(len(s.conf_t), len(s.conf_v))
    conf = [{"t": iso(t), "glucose_mg_dl": v, "kind": "confirmed"} for t, v in zip(s.conf_t[:n], s.conf_v[:n]) if t >= since]
    out = {"now": now, "confirmed": conf, "estimate": est, "forecast": fc, "gummi_view": view}
    _cache[pid] = (key, out)
    return out


def mood(u, v: dict | None) -> str:
    now = time.time()
    if v is None:
        return "calm"
    lo, hi = u.profile["low_line_mg_dl"], u.profile["high_line_mg_dl"]
    pts = [p["glucose_mg_dl"] for p in v["estimate"] + v["forecast"]]
    if pts and min(pts) <= lo:
        return "low"
    if v["forecast"] and max(p["glucose_mg_dl"] for p in v["forecast"]) >= hi:
        return "high"
    if now < u.proud_until:
        return "proud"
    trend = v["gummi_view"]["trend"]
    if trend == "falling_fast":
        return "dipping"
    if trend in ("rising", "rising_fast"):
        return "rising"
    recent = [p["glucose_mg_dl"] for p in v["confirmed"][-36:]]
    if now < u.happy_until or (len(recent) >= 36 and all(lo < g < hi for g in recent)):
        return "happy"
    h = v["now"].astimezone(TZ).hour
    if h >= 23 or h < 6:
        return "sleepy"
    return "calm"


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return r1(float(np.mean(xs))) if xs else None


def build_state(uid: str) -> dict:
    u = store.get(uid)
    pid = u.following
    s = engine.subjects.get(pid) if pid else None
    v = subject_view(pid) if pid else None
    status = stream_status()
    today = {"time_in_range_pct": 0.0, "peak_mg_dl": 0.0, "meals": len(u.meals), "steps": u.steps, "walks": len(u.walks),
             "gummi_mae_mg_dl": None, "cgm_only_mae_mg_dl": None, "last_value_mae_mg_dl": None}
    pending, alert = [], None
    if s is not None and v is not None:
        day = v["now"].astimezone(TZ).date()
        vals = [c["glucose_mg_dl"] for c, t in zip(v["confirmed"], s.conf_t[-len(v["confirmed"]):])
                if t.astimezone(TZ).date() == day]
        lo, hi = u.profile["low_line_mg_dl"], u.profile["high_line_mg_dl"]
        grades_today = [g for g in list(s.grades) if g["graded_at"][:10] == day.isoformat()]
        today.update({"time_in_range_pct": r1(100 * sum(lo <= g <= hi for g in vals) / len(vals)) if vals else 0.0,
                      "peak_mg_dl": max(vals) if vals else 0.0,
                      "meals": sum(m["eaten_at"][:10] == day.isoformat() for m in s.meals),
                      "gummi_mae_mg_dl": _mean(g["gummi_mae_mg_dl"] for g in grades_today),
                      "cgm_only_mae_mg_dl": _mean(g["cgm_only_mae_mg_dl"] for g in grades_today),
                      "last_value_mae_mg_dl": _mean(g["last_value_mae_mg_dl"] for g in grades_today)})
        pending = [engine.public_prediction(p) for p in list(s.predictions.values()) if p["status"] == "pending"][-10:]
        if u.alert and u.alert["expires_at"] >= iso(v["now"]):
            alert = u.alert
    return {
        "user_id": uid, "following": pid, "acting_as": pid if s is not None else None, "dexcom": dexcom_status(),
        "gummi_view": v["gummi_view"] if v else None,
        "confirmed": v["confirmed"] if v else [], "estimate": v["estimate"] if v else [],
        "forecast": v["forecast"] if v else [],
        "mood": mood(u, v), "alert": alert, "top_card": u.cards[-1] if u.cards else None,
        "pending_predictions": pending, "today": today,
        "profile": {"high_line_mg_dl": u.profile["high_line_mg_dl"], "low_line_mg_dl": u.profile["low_line_mg_dl"]},
        "upcoming_due": engine.upcoming_due(pid),
        "replay_now": iso(v["now"]) if v and clock.running else None, "stream": status,
        "model_version": engine.model.version if engine.model else config.MODEL_VERSION,
        "server_time": iso(datetime.now(TZ)),
    }


def fleet() -> dict:
    entries = []
    for pid in config.PARTICIPANTS:
        s = engine.subjects.get(pid)
        graded = list(s.grades) if s else []
        acc = gold.by_user.get(pid, {})
        if (acc.get("grades") or 0) < 0.5 * len(graded):
            acc = {}
        last = graded[-1] if graded else None
        conf = list(zip(s.conf_t, s.conf_v)) if s else []
        spark = [{"t": iso(t), "glucose_mg_dl": g, "kind": "confirmed"} for t, g in conf[-36::3]]
        entries.append({
            "user_id": pid, "display_name": store.display_name(pid), "mood": _fleet_mood(conf, last),
            "data_through": iso(conf[-1][0]) if conf else None, "sparkline": spark,
            "grades": int(acc.get("grades") or len(graded)),
            "gummi_mae_mg_dl": acc.get("gummi_mae_mg_dl", _mean(g["gummi_mae_mg_dl"] for g in graded)),
            "cgm_only_mae_mg_dl": acc.get("cgm_only_mae_mg_dl", _mean(g["cgm_only_mae_mg_dl"] for g in graded)),
            "last_value_mae_mg_dl": acc.get("last_value_mae_mg_dl", _mean(g["last_value_mae_mg_dl"] for g in graded)),
            "last_grade": last})
    all_g = [g for s in list(engine.subjects.values()) for g in list(s.grades)]
    # Gold numbers only once the pipeline has caught up with this replay session (stale or test rows never show)
    roll = gold.rollup if gold.rollup and (gold.rollup.get("grades") or 0) >= 0.5 * len(all_g) else {}
    return {"entries": entries,
            "fleet_gummi_mae_mg_dl": roll.get("gummi_mae_mg_dl", _mean(g["gummi_mae_mg_dl"] for g in all_g)),
            "fleet_cgm_only_mae_mg_dl": roll.get("cgm_only_mae_mg_dl", _mean(g["cgm_only_mae_mg_dl"] for g in all_g)),
            "fleet_last_value_mae_mg_dl": roll.get("last_value_mae_mg_dl", _mean(g["last_value_mae_mg_dl"] for g in all_g)),
            "stream": stream_status()}


def _fleet_mood(conf, last) -> str:
    if not conf:
        return "calm"
    g = conf[-1][1]
    slope = (conf[-1][1] - conf[-4][1]) / 15 if len(conf) >= 4 else 0
    if g <= config.LOW_LINE:
        return "low"
    if g >= config.HIGH_LINE:
        return "high"
    if slope <= -2:
        return "dipping"
    if slope >= 1:
        return "rising"
    return "calm"
