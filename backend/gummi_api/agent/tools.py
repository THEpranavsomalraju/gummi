"""Agent tools (CONTRACT section 7), shared by chat and the event-driven agent. Each returns (result_for_llm, card).

Results are small JSON so every LLM step stays fast; cards go to the phone as chat cards (CONTRACT section 6).
Every number the agent says must come from one of these.
"""
import json
import logging
from datetime import timedelta

import pandas as pd

from .. import config
from ..engine.engine import MACROS, engine
from ..engine.gold import gold
from ..errors import ApiError
from ..nutrition.estimate import SEED, item, lookup
from ..state.hot_store import store
from ..state.view import build_state, subject_view
from ..stream.producer import clock
from ..util import TZ, iso, r1

log = logging.getLogger("gummi.tools")

_ITEMS = {"type": "array", "description": "Foods with portions. For foods that aren't common staples, estimate macros for the whole portion.",
          "items": {"type": "object", "required": ["name"], "properties": {
              "name": {"type": "string"}, "quantity": {"type": "number"}, "unit": {"type": "string"},
              "carbs_g": {"type": "number"}, "sugar_g": {"type": "number"}, "fiber_g": {"type": "number"},
              "protein_g": {"type": "number"}, "fat_g": {"type": "number"}, "calories": {"type": "number"}}}}

SCHEMAS = [
    {"name": "get_state", "description": "Only for questions about right now (am I high, how am I doing, what's my glucose doing). Your estimate for now (with band and trend), the last confirmed Dexcom reading, the 2-hour forecast peak, today's numbers and the next due meal.",
     "parameters": {"type": "object", "properties": {}}},
    {"name": "simulate_food", "description": "What eating these foods would likely do: peak with and without, verdict, and alternatives (half portion, walk after). Use for any 'can I eat/should I have' question, and for meals mentioned while acting as a study participant.",
     "parameters": {"type": "object", "required": ["items"], "properties": {"items": _ITEMS,
                    "in_minutes": {"type": "number", "description": "Minutes from now; 0 or omitted means now."}}}},
    {"name": "log_meal", "description": "Save a meal the person ate or is eating now.",
     "parameters": {"type": "object", "required": ["items"], "properties": {"items": _ITEMS}}},
    {"name": "suggest_walk", "description": "Whether a walk now would help: forecast peak, modeled drop for a 10-minute walk, and the effect's source.",
     "parameters": {"type": "object", "properties": {"minutes": {"type": "number"}}}},
    {"name": "get_history", "description": "Readings summary, meals, walks and graded predictions over the last N hours.",
     "parameters": {"type": "object", "properties": {"hours": {"type": "number"}}}},
    {"name": "explain_spike", "description": "The biggest rise in the last N hours: peak, the meals before it with carbs, walks, and what Gummi predicted versus what happened.",
     "parameters": {"type": "object", "properties": {"hours": {"type": "number"}}}},
    {"name": "today_summary", "description": "Today's time in range, peak, meals, steps, walks, and your prediction accuracy next to CGM-only and last value.",
     "parameters": {"type": "object", "properties": {}}},
    {"name": "get_gold_summary", "description": "Accuracy from the Databricks gold tables for this person over N days, plus the all-participant rollup, always with CGM-only and last value. Out-of-sample for study participants.",
     "parameters": {"type": "object", "properties": {"days": {"type": "number"}}}},
    {"name": "ask_data", "description": "Slow (can take 20+ seconds): a deep look at this person's own past patterns through Gummi Insights on Databricks, e.g. which meals spike them most across all days, or how walks after meals changed their peaks. Only when the other tools can't answer.",
     "parameters": {"type": "object", "required": ["question"], "properties": {"question": {"type": "string"}}}},
]
OPENAI_TOOLS = [{"type": "function", "function": s} for s in SCHEMAS]
CHAT_TOOLS = [t for t in OPENAI_TOOLS]


class Ctx:
    """Who the agent is talking to and whose glucose it reasons about."""
    def __init__(self, uid: str):
        self.uid = uid
        self.u = store.get(uid)
        self.pid = self.u.following
        self.subject = engine.subjects.get(self.pid) if self.pid else None


RELIABLE_CARBS_G = 140.0      # 95% of the study meals the model learned from had 138 g of carbs or less


def _requested_carbs(raw: list[dict]) -> float:
    """Carbs the person actually asked about, before any portion cap (50 cookies is 50 cookies)."""
    total = 0.0
    for r in raw or []:
        if r.get("carbs_g") is not None and lookup(str(r.get("name", "")))[1] != "seed":
            total += float(r["carbs_g"])
            continue
        per, _ = lookup(str(r.get("name", "")))
        unit = str(r.get("unit") or "").lower().rstrip(".")
        q = 1.0 if unit in ("g", "gram", "grams", "oz", "ml") else float(r.get("quantity") or 1)
        total += per["carbs_g"] * q
    return r1(total)


def _foods(raw: list[dict]) -> list[dict]:
    out = []
    for r in raw or []:
        name = str(r.get("name") or "").strip()
        if not name:
            continue
        given = {k: r[k] for k in (*MACROS, "calories") if r.get(k) is not None}
        _, source = lookup(name)
        if source == "seed":
            out.append(item(name, r.get("quantity") or 1, r.get("unit")))
        else:
            q = float(r.get("quantity") or 1)
            per = {k: float(v) for k, v in given.items()}
            out.append(item(name, q, r.get("unit"), **{k: per.get(k, 0.0) for k in (*MACROS, "calories")},
                            nutrition_source="llm_estimate") if given else item(name, q, r.get("unit")))
    if not out:
        raise ApiError(422, "invalid", "no foods given")
    return out


def _now():
    return clock.replay_to_wall(clock.now()) if clock.now() is not None else None


def _hm(ts) -> str:
    return pd.Timestamp(ts).tz_convert(TZ).strftime("%-I:%M %p")


# ---------- tools ----------

def get_state(c: Ctx, **_):
    s = build_state(c.uid)
    if s["data_status"] == "stale":
        hrs = round((s["minutes_since_reading"] or 0) / 60, 1)
        return {"available": False, "data_status": "stale", "hours_since_last_reading": hrs,
                "note": f"No Dexcom readings for {hrs} hours, so there is no estimate. Do NOT guess or say they're in "
                        "range. Say there are no recent readings and suggest checking the Dexcom app."}, None
    if not s["gummi_view"]:
        return {"available": False, "note": "No glucose data: not following a participant."}, None
    v, conf, fc = s["gummi_view"], s["confirmed"], s["forecast"]
    peak = max(fc, key=lambda p: p["glucose_mg_dl"]) if fc else None
    res = {"my_estimate_now": v["glucose_mg_dl"], "band": [v["band_low_mg_dl"], v["band_high_mg_dl"]], "trend": v["trend"],
           "confidence": v["confidence"], "last_dexcom_reading": conf[-1]["glucose_mg_dl"] if conf else None,
           "minutes_since_reading": v["minutes_since_confirmed"],
           "forecast_peak_2h": {"mg_dl": peak["glucose_mg_dl"], "at": _hm(peak["t"])} if peak else None,
           "high_line": s["profile"]["high_line_mg_dl"], "local_time": _hm(_now()) if _now() else None,
           "estimate_vs_range": ("above" if v["glucose_mg_dl"] >= s["profile"]["high_line_mg_dl"] else
                                 "below" if v["glucose_mg_dl"] <= s["profile"]["low_line_mg_dl"] else "in range"),
           "today": s["today"], "next_due_meal": s["upcoming_due"][0]["body"] if s["upcoming_due"] else None,
           "acting_as": s["acting_as"]}
    return res, {"card_type": "gummi_view", "payload": v}


def simulate_food(c: Ctx, items=None, in_minutes=0, **_):
    from ..routes.meals import run_simulation
    foods = _foods(items)
    eat = (_now() + timedelta(minutes=float(in_minutes or 0))).isoformat() if in_minutes and _now() else None
    sim = run_simulation(c.uid, foods, eat)
    asked = _requested_carbs(items)
    modeled = r1(sum(f["carbs_g"] for f in foods))
    reliable = asked <= RELIABLE_CARBS_G
    sim["reliable"] = reliable
    sim["requested_carbs_g"] = asked
    res = {"foods": [f"{f['quantity']:g} {f['unit']} {f['name']}" for f in foods],
           "carbs_g": modeled, "requested_carbs_g": asked, "nutrition_source": sorted({f["nutrition_source"] for f in foods}),
           "peak_with_food": sim["peak_mg_dl"], "peak_at": _hm(sim["peak_at"]),
           "peak_without_food": max(p["glucose_mg_dl"] for p in sim["baseline_curve"]),
           "verdict": sim["verdict"], "high_line": c.u.profile["high_line_mg_dl"],
           "alternatives": sim["alternatives"], "method": sim["method"]}
    if asked > modeled + 1:
        res["portion_note"] = f"Modeled as {modeled:.0f} g carbs (portions capped at 6); they asked about {asked:.0f} g."
    if not reliable:
        res = {k: v for k, v in res.items() if k not in ("peak_with_food", "peak_at", "alternatives")}
        res["reliable"] = False
        res["note"] = (f"About {asked:.0f} g of carbs is more than 95% of the meals I learned from (most were under "
                       f"140 g), so I can't give a trustworthy peak. Say that plainly and kindly: it would very likely "
                       f"push them well above {c.u.profile['high_line_mg_dl']:.0f} mg/dL. Do not quote a peak number.")
    return res, {"card_type": "simulation", "payload": sim}


def log_meal(c: Ctx, items=None, **_):
    from ..routes.meals import create_meal
    meal = create_meal(c.uid, _foods(items), "chat")
    res = {"added_to_food_log": True, "meal_id": meal["meal_id"], "carbs_g": meal["totals"]["carbs_g"]}
    sim = c.u.meal_sims.get(meal["meal_id"])
    if c.subject is not None and sim:
        # D-59: on a study participant's day the entry is simulated and never graded (they didn't really eat it)
        res.update({"likely_peak_mg_dl": sim["predicted_peak_mg_dl"], "peak_at": _hm(sim["peak_at"]),
                    "verdict": sim["verdict"], "graded": False,
                    "note": f"Added to the food log as a simulated entry on {store.display_name(c.pid)}'s day; "
                            "it won't be graded. Say so in one short line."})
    else:
        res["note"] = "No glucose data connected for this person, so no prediction."
    payload = {**meal, "simulated": bool(c.subject is not None and sim),
               "likely_peak_mg_dl": sim["predicted_peak_mg_dl"] if sim else None,
               "peak_at": iso(pd.Timestamp(sim["peak_at"])) if sim else None}
    return res, {"card_type": "meal_saved", "payload": payload}


def suggest_walk(c: Ctx, minutes=10, **_):
    s = c.subject
    if s is None or _now() is None or engine.stale(s, clock.now()):
        return {"available": False, "note": "No recent readings, so no forecast to walk against."}, None
    minutes = float(minutes or 10)
    fc = s.model.forecast(engine.ctx(s), _now(), 120)
    peak = max(fc, key=lambda p: p["glucose_mg_dl"]) if fc else None
    eff = s.model.walk_effect(engine.ctx(s), minutes, "moderate")
    res = {"forecast_peak": peak["glucose_mg_dl"] if peak else None, "peak_at": _hm(peak["t"]) if peak else None,
           "walk_minutes": minutes, "modeled_peak_drop_mg_dl": eff.get("forecast_peak_drop_mg_dl"),
           "peak_after_walk": r1(peak["glucose_mg_dl"] - (eff.get("forecast_peak_drop_mg_dl") or 0)) if peak else None,
           "peak_is_over_high_line": bool(peak and peak["glucose_mg_dl"] >= c.u.profile["high_line_mg_dl"]),
           "effect_source": eff.get("effect_source"), "high_line": c.u.profile["high_line_mg_dl"]}
    card = {"card_type": "walk_suggestion", "payload": {"minutes": int(minutes), "start": iso(_now()),
            "forecast_peak_mg_dl": res["forecast_peak"], "forecast_peak_drop_mg_dl": res["modeled_peak_drop_mg_dl"],
            "effect_source": res["effect_source"]}}
    return res, card


def _window(c: Ctx, hours: float):
    s = c.subject
    end = _now()
    start = end - timedelta(hours=float(hours or 6))
    n = min(len(s.conf_t), len(s.conf_v))
    pts = [(t, v) for t, v in zip(s.conf_t[:n], s.conf_v[:n]) if t >= start]
    return s, start, end, pts


def get_history(c: Ctx, hours=6, **_):
    if c.subject is None:
        return {"available": False}, None
    s, start, end, pts = _window(c, hours)
    vals = [v for _, v in pts]
    meals = [{"at": _hm(m["eaten_at"]), "food": m["items"][0]["name"], "carbs_g": m["totals"]["carbs_g"]}
             for m in s.meals if pd.Timestamp(m["eaten_at"]) >= start]
    grades = [{"about": s.predictions.get(g["prediction_id"], {}).get("about"), "gummi_mae": g["gummi_mae_mg_dl"],
               "cgm_only_mae": g["cgm_only_mae_mg_dl"], "last_value_mae": g["last_value_mae_mg_dl"]}
              for g in list(s.grades)[-6:]]
    return {"hours": hours, "readings": len(vals), "min": min(vals, default=None), "max": max(vals, default=None),
            "avg": r1(sum(vals) / len(vals)) if vals else None, "meals": meals[-8:],
            "walks": [{"minutes": w["minutes"], "intensity": w["intensity"]} for w in c.u.walks[-3:]],
            "recent_grades": grades}, None


def explain_spike(c: Ctx, hours=6, **_):
    if c.subject is None:
        return {"available": False}, None
    s, start, end, pts = _window(c, hours)
    if len(pts) < 3:
        return {"available": False, "note": "not enough readings yet"}, None
    t_peak, v_peak = max(pts, key=lambda p: p[1])
    before = [v for t, v in pts if t <= t_peak - timedelta(minutes=60)]
    meals = [{"at": _hm(m["eaten_at"]), "food": m["items"][0]["name"], "carbs_g": m["totals"]["carbs_g"],
              "sugar_g": m["totals"]["sugar_g"], "fiber_g": m["totals"]["fiber_g"]}
             for m in s.meals if t_peak - timedelta(hours=3) <= pd.Timestamp(m["eaten_at"]) <= t_peak]
    pred = next((p for p in reversed(list(s.predictions.values())) if p["kind"] == "meal" and p.get("meal_id")
                 and start <= pd.Timestamp(p["window_start"]) <= t_peak), None)
    return {"peak_mg_dl": v_peak, "peak_at": _hm(t_peak), "rise_mg_dl": r1(v_peak - before[-1]) if before else None,
            "glucose_before_mg_dl": before[-1] if before else None,
            "total_carbs_before_peak_g": r1(sum(m["carbs_g"] for m in meals)), "meals_before": meals, "walks": len(c.u.overlay_walks),
            "gummi_predicted_peak": pred["predicted_peak_mg_dl"] if pred else None,
            "cgm_only_predicted_peak": pred["cgm_only_peak_mg_dl"] if pred else None}, None


def today_summary(c: Ctx, **_):
    s = build_state(c.uid)
    return {**s["today"], "high_line": s["profile"]["high_line_mg_dl"],
            "accuracy_note": "maes are today's graded predictions; null before the first grade"}, None


def get_gold_summary(c: Ctx, days=1, **_):
    who = c.pid or c.uid
    if not gold.rows and c.subject is not None and c.subject.grades:
        # gold not loaded yet: the App's own grades (same grade() output the pipeline aggregates), labeled as such
        gs = list(c.subject.grades)
        mean = lambda k: r1(sum(g[k] for g in gs if g[k] is not None) / max(1, sum(g[k] is not None for g in gs)))  # noqa: E731
        return {"source": "live grades in the App (gold tables not loaded yet)", "grades": len(gs),
                "gummi_mae_mg_dl": mean("gummi_mae_mg_dl"), "cgm_only_mae_mg_dl": mean("cgm_only_mae_mg_dl"),
                "last_value_mae_mg_dl": mean("last_value_mae_mg_dl"), "sample": "out-of-sample"}, None
    rows = [{k: r.get(k) for k in ("sample", "user_id", "window_type", "grades", "gummi_mae_mg_dl", "cgm_only_mae_mg_dl",
                                   "last_value_mae_mg_dl", "gummi_beats_cgm_only_pct")} for r in gold.summary(who)]
    return {"source": "stream_gold_accuracy (Databricks)", "refreshed_at": gold.refreshed_at, "rows": rows[:12]}, None


def ask_data(c: Ctx, question="", **_):
    from .llm import ask_insights
    who = c.pid or c.uid
    answer = ask_insights(f"About {who} ({store.display_name(who)}): {question}")
    if answer:
        return {"answer": answer, "source": "Gummi Insights (Databricks Agent Bricks)"}, None
    res, _ = get_gold_summary(c)
    res["note"] = "Gummi Insights timed out; this is the gold summary instead."
    return res, None


IMPL = {"get_state": get_state, "simulate_food": simulate_food, "log_meal": log_meal, "suggest_walk": suggest_walk,
        "get_history": get_history, "explain_spike": explain_spike, "today_summary": today_summary,
        "get_gold_summary": get_gold_summary, "ask_data": ask_data}


def run(name: str, args: dict, c: Ctx):
    try:
        return IMPL[name](c, **(args or {}))
    except ApiError as e:
        return {"error": e.code, "message": e.message}, None
    except Exception as e:  # noqa: BLE001 (the agent gets the failure and says so)
        log.exception("tool %s failed", name)
        return {"error": "tool_failed", "message": str(e)[:200]}, None


def dumps(x) -> str:
    return json.dumps(x, default=str, separators=(",", ":"))


__all__ = ["OPENAI_TOOLS", "CHAT_TOOLS", "Ctx", "run", "dumps", "SEED", "config"]
