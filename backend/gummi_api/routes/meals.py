"""Meals, meal_due logging, simulate, vitals, walk events (CONTRACT section 4), backed by the replay engine."""
import time
from datetime import timedelta

import pandas as pd
from fastapi import APIRouter, Depends

from .. import activity
from ..auth import user_id
from ..engine.engine import MACROS, engine
from ..errors import ApiError
from ..live.broadcaster import broadcaster
from ..nutrition.estimate import item, totals
from ..state import cards
from ..state.hot_store import store
from ..stream.landing_writer import landing
from ..stream.producer import clock
from ..util import iso, iso_utc, new_id, parse, r1, utcnow
from .core import push_state

router = APIRouter()


def _items(raw: list[dict]) -> list[dict]:
    if not raw:
        raise ApiError(422, "invalid", "items must not be empty")
    out = []
    for r in raw:
        if not r.get("name"):
            raise ApiError(422, "invalid", "every item needs a name")
        out.append(item(r["name"], r.get("quantity", 1), r.get("unit"),
                        **{k: r[k] for k in ("carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g", "calories",
                                             "nutrition_source") if k in r}))
    return out


def _acting(uid: str):
    pid = store.get(uid).following
    return engine.subjects.get(pid) if pid else None


def create_meal(uid: str, items: list[dict], source: str) -> dict:
    """An entry in the teammate's food log, manual ("manual") or added by Gummi from chat ("chat").

    While acting as a replay participant (D-53, D-59) the entry sits on the participant's day, at the replay clock,
    with Gummi's simulated prediction attached. It never feeds the replay and is never graded: that participant
    didn't really eat it, so scoring it against their real glucose would be dishonest."""
    u = store.get(uid)
    s = _acting(uid)
    when = clock.replay_to_wall(clock.now()) if s is not None and clock.now() is not None else utcnow()
    meal = {"meal_id": new_id("m"), "eaten_at": iso(when), "source": source, "items": items,
            "totals": totals(items), "is_standard_breakfast": False, "prediction_id": None}
    body = "Saved to your food log."
    if s is not None:
        try:
            sim = run_simulation(uid, items)
            u.meal_sims[meal["meal_id"]] = {"predicted_peak_mg_dl": sim["peak_mg_dl"], "peak_at": sim["peak_at"],
                                            "verdict": sim["verdict"], "without_food_peak_mg_dl":
                                            max(p["glucose_mg_dl"] for p in sim["baseline_curve"])}
            body = (f"Added to your food log. I think this likely peaks near {sim['peak_mg_dl']:.0f} mg/dL. It's "
                    f"simulated on {store.display_name(s.pid)}'s day, so I won't grade it.")
        except ApiError:
            pass
    u.meals.append(meal)
    landing.enqueue({"source": "app", "user_id": uid, "kind": "meal", "t": iso_utc(when),
                     "released_at": iso_utc(utcnow()), "payload": meal})
    c = cards.card("meal_logged", when, f"{items[0]['name'].capitalize()} logged", body, "calm",
                   attachments={"meal": meal})
    u.add_card(c)
    broadcaster.publish(uid, "card", c)
    push_state(uid)
    return meal


def foodlog_entries(uid: str, date: str | None = None) -> list[dict]:
    """The day's food log: the study participant's real meals (graded) plus the teammate's own entries."""
    u = store.get(uid)
    s = _acting(uid)
    out = []
    if s is not None:
        graded = {g["prediction_id"]: g for g in list(s.grades)}
        for m in list(s.meals):
            p = s.predictions.get(m["prediction_id"]) if m["prediction_id"] else None
            g = graded.get(m["prediction_id"]) if m["prediction_id"] else None
            out.append({"meal": m, "origin": "study_log", "graded": g is not None,
                        "prediction": {k: p[k] for k in ("predicted_peak_mg_dl", "cgm_only_peak_mg_dl",
                                                         "last_value_peak_mg_dl", "status")} if p else None,
                        "grade": g,
                        "note": None if p else "Before the replay started, so no prediction"})
    for m in list(u.meals):
        sim = u.meal_sims.get(m["meal_id"])
        out.append({"meal": m, "origin": "gummi" if m["source"] == "chat" else "you", "graded": False,
                    "prediction": {"predicted_peak_mg_dl": sim["predicted_peak_mg_dl"], "cgm_only_peak_mg_dl": None,
                                   "last_value_peak_mg_dl": None, "status": "pending"} if sim else None,
                    "grade": None,
                    "note": "Simulated on the participant's day; not graded" if sim else None})
    if date:
        out = [e for e in out if e["meal"]["eaten_at"][:10] == date]
    return sorted(out, key=lambda e: e["meal"]["eaten_at"], reverse=True)


@router.get("/foodlog")
async def foodlog(uid: str = Depends(user_id), date: str | None = None):
    return {"date": date, "entries": foodlog_entries(uid, date)[:200]}


def _find(uid: str, meal_id: str):
    s = _acting(uid)
    for m in (s.meals if s else []):
        if m["meal_id"] == meal_id:
            return s, m
    for m in store.get(uid).meals:
        if m["meal_id"] == meal_id:
            return None, m
    raise ApiError(404, "not_found", f"meal {meal_id} not found")


@router.post("/meals")
async def post_meal(body: dict, uid: str = Depends(user_id)):
    source = body.get("source", "manual")
    if source not in ("chat", "manual"):
        raise ApiError(422, "invalid", "source must be chat or manual")
    return create_meal(uid, _items(body.get("items", [])), source)


@router.patch("/meals/{meal_id}")
async def patch_meal(meal_id: str, body: dict, uid: str = Depends(user_id)):
    with engine.lock:
        return _patch(uid, meal_id, body)


def _patch(uid: str, meal_id: str, body: dict) -> dict:
    s, meal = _find(uid, meal_id)
    meal["items"] = _items(body.get("items", []))
    meal["totals"] = totals(meal["items"])
    if s is not None:
        # portions corrected: update the model input and recompute the prediction (CONTRACT section 4)
        for row in s.meal_inputs:
            if row["meal_id"] == meal_id:
                row.update({k: meal["totals"][k] for k in MACROS})
        old = s.predictions.pop(meal["prediction_id"], None) if meal["prediction_id"] else None
        if old is None or old["status"] == "pending":
            eaten_r = (pd.Timestamp(meal["eaten_at"]) - pd.Timestamp(clock.replay_to_wall(0))).total_seconds() / 60
            meal["prediction_id"] = engine._meal_prediction(s, meal, eaten_r)["prediction_id"]
        s.version += 1
    push_state(uid)
    return meal


@router.delete("/meals/{meal_id}")
async def delete_meal(meal_id: str, uid: str = Depends(user_id)):
    with engine.lock:
        return _delete(uid, meal_id)


def _delete(uid: str, meal_id: str) -> dict:
    s, meal = _find(uid, meal_id)
    if s is not None:
        s.meals.remove(meal)
        s.meal_inputs = [r for r in s.meal_inputs if r["meal_id"] != meal_id]
        if meal["prediction_id"]:
            s.predictions.pop(meal["prediction_id"], None)
        s.version += 1
    else:
        store.get(uid).meals.remove(meal)
    push_state(uid)
    return {"deleted": True}


@router.get("/meals")
async def get_meals(uid: str = Depends(user_id), date: str | None = None):
    s = _acting(uid)
    meals = (s.meals if s else store.get(uid).meals)
    if date:
        meals = [m for m in meals if m["eaten_at"][:10] == date]
    return {"meals": meals[-100:]}


@router.post("/meals/due/{due_id}/log")
async def log_due(due_id: str, uid: str = Depends(user_id)):
    try:
        meal = engine.log_due(due_id, "replay_due")
    except RuntimeError:
        raise ApiError(409, "due_already_logged", f"{due_id} was logged already")
    if meal is None:
        raise ApiError(404, "not_found", f"due meal {due_id} not found")
    push_state(uid)
    return meal


def run_simulation(uid: str, items: list[dict], eat_at=None) -> dict:
    s = _acting(uid)
    if s is None or len(s.conf_t) < 3 or clock.now() is None:
        raise ApiError(409, "no_cgm_data", "Follow a participant first: simulations need glucose data")
    now = clock.replay_to_wall(clock.now())
    eat = parse(eat_at) if eat_at else now
    sim = s.model.simulate(engine.ctx(s), now, [{k: i[k] for k in MACROS} for i in items], eat_at=eat)
    name = items[0]["name"] if len(items) == 1 else "that"
    pred_id = new_id("pr")
    curve = sim["with_food_curve"]
    s.predictions[pred_id] = {
        "prediction_id": pred_id, "kind": "meal", "made_at": iso(now), "about": f"simulated {name}", "meal_id": None,
        "window_start": iso(eat), "window_end": iso(eat + timedelta(hours=2)), "predicted_peak_mg_dl": sim["peak_mg_dl"],
        "predicted_curve": curve, "cgm_only_peak_mg_dl": None, "last_value_peak_mg_dl": r1(s.conf_v[-1]),
        "status": "graded", "_cgm_only_curve": []}   # hypothetical food: never graded against real glucose
    return {"items": items, "eat_at": sim["eat_at"], "baseline_curve": sim["baseline_curve"],
            "with_food_curve": curve, "peak_mg_dl": sim["peak_mg_dl"], "peak_at": sim["peak_at"],
            "verdict": sim["verdict"], "summary": f"With the {name} you'd likely peak near {sim['peak_mg_dl']:.0f}.",
            "alternatives": sim["alternatives"], "method": sim["method"], "prediction_id": pred_id}


@router.post("/simulate")
async def simulate(body: dict, uid: str = Depends(user_id)):
    return run_simulation(uid, _items(body.get("items", [])), body.get("eat_at"))


@router.post("/vitals")
async def vitals(body: dict, uid: str = Depends(user_id)):
    samples = [s for s in body.get("samples", []) if s.get("type") == "steps" and s.get("value") is not None]
    store.get(uid).steps += int(sum(s["value"] for s in samples))
    if samples:
        activity.hit("source.iphone", len(samples), detail=f"{uid}: {int(sum(s['value'] for s in samples))} steps")
    for smp in samples:
        landing.enqueue({"source": "iphone", "user_id": uid, "kind": "steps", "t": smp.get("end") or iso_utc(utcnow()),
                         "released_at": iso_utc(utcnow()),
                         "payload": {"value": smp["value"], "start": smp.get("start"), "end": smp.get("end")}})
    return {"accepted": len(samples)}


@router.post("/events")
async def events(body: dict, uid: str = Depends(user_id)):
    u = store.get(uid)
    at = parse(body["at"]) if body.get("at") else utcnow()
    kind = body.get("type")
    if kind == "walk_started":
        u.walk_started_at, u.walk_started_r = at, clock.now()
    elif kind == "walk_completed":
        started = parse(body["started_at"]) if body.get("started_at") else u.walk_started_at or at - timedelta(minutes=10)
        minutes = max(1, round((at - started).total_seconds() / 60))
        steps = int(body.get("steps") or minutes * 105)
        cadence = int(body.get("cadence_spm") or round(steps / minutes))
        s = _acting(uid)
        try:
            from gummi_activity import intensity_from_cadence
            intensity = intensity_from_cadence(cadence)["intensity"]
        except Exception:  # noqa: BLE001
            intensity = "moderate" if cadence >= 100 else "light"
        eff = s.model.walk_effect(engine.ctx(s), minutes, intensity) if s else {}
        walk = {"started_at": iso(started), "ended_at": iso(at), "minutes": minutes, "steps": steps,
                "cadence_spm": cadence, "intensity": intensity,
                "forecast_peak_drop_mg_dl": r1(eff.get("forecast_peak_drop_mg_dl", 0.0)),
                "effect_source": eff.get("effect_source", "literature")}
        u.walks.append(walk)
        if s is not None and u.walk_started_r is not None:
            # D-28: the walk overlays the followed participant at the replay time it started, for its real length
            u.overlay_walks.append({"started_at": iso_utc(clock.replay_to_wall(u.walk_started_r)), "minutes": minutes})
            s.version += 1
        u.walk_started_at, u.walk_started_r, u.alert = None, None, None
        u.happy_until = time.time() + 20 * 60
        activity.hit("source.iphone", detail=f"{uid}: walk {minutes} min", log=True)
        landing.enqueue({"source": "iphone", "user_id": uid, "kind": "walk", "t": iso_utc(at),
                         "released_at": iso_utc(utcnow()), "payload": walk})
        note = "" if s is None else " Your real walk is shown over the replayed day; its effect on replayed glucose isn't graded."
        when = clock.replay_to_wall(clock.now()) if s is not None and clock.now() is not None else utcnow()
        c = cards.card("walk_summary", when, "Nice walk",
                       f"{minutes} minutes, {steps:,} steps, {intensity} pace. Modeled effect: about "
                       f"{walk['forecast_peak_drop_mg_dl']:.0f} mg/dL lower peak ({walk['effect_source']}).{note}",
                       "happy", attachments={"walk": walk})
        u.add_card(c)
        broadcaster.publish(uid, "card", c)
        broadcaster.publish(uid, "mood", {"mood": "happy"})
        push_state(uid)
    else:
        raise ApiError(422, "invalid", "type must be walk_started or walk_completed")
    return {"ok": True}


@router.get("/walks/latest")
async def latest_walk(uid: str = Depends(user_id)):
    u = store.get(uid)
    if not u.walks:
        raise ApiError(404, "not_found", "no walks yet")
    return u.walks[-1]
