"""Meals, meal_due logging, simulate, vitals, walk events (CONTRACT section 4). Mock engine until gummi_model lands."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException

from .. import config
from ..auth import user_id
from ..live.broadcaster import broadcaster
from ..mock import data as mock
from ..nutrition.estimate import item, totals
from ..state.hot_store import store
from ..util import iso, new_id, parse, utcnow
from .core import counters, current_state

router = APIRouter()
DUE_MEALS = {"d_1": "Two waffles with syrup and a black coffee", "d_2": "Turkey sandwich and an apple",
             "d_3": "Greek yogurt with honey", "d_4": "Chicken stir fry with rice"}


def _items(raw: list[dict]) -> list[dict]:
    if not raw:
        raise HTTPException(422, "items must not be empty")
    out = []
    for r in raw:
        if not r.get("name"):
            raise HTTPException(422, "every item needs a name")
        out.append(item(r["name"], r.get("quantity", 1), r.get("unit"),
                        **{k: r[k] for k in ("carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g", "calories",
                                             "nutrition_source") if k in r}))
    return out


def _predict(uid: str, about: str, at, items: list[dict], meal_id: str | None) -> dict:
    s = current_state(uid)
    last = s["confirmed"][-1]["glucose_mg_dl"]
    carbs = totals(items)["carbs_g"]
    curve = mock.forecast(store.get(uid).following or uid, at, bump=carbs * 0.9, bump_in_min=0)[:24]
    peak = max(p["glucose_mg_dl"] for p in curve)
    p = mock.prediction(about, at, peak, last, curve, meal_id=meal_id)
    store.get(uid).predictions[p["prediction_id"]] = p
    counters["predictions"] += 1
    return p


def _about(items: list[dict]) -> str:
    return ", ".join(f"{i['name']}" + (f" x{i['quantity']:g}" if i["quantity"] != 1 else "") for i in items)


def create_meal(uid: str, items: list[dict], eaten_at, source: str) -> dict:
    meal_id = new_id("m")
    pred = _predict(uid, _about(items), eaten_at, items, meal_id)
    meal = {"meal_id": meal_id, "eaten_at": iso(eaten_at), "source": source, "items": items,
            "totals": totals(items), "prediction_id": pred["prediction_id"]}
    u = store.get(uid)
    u.meals.append(meal)
    c = mock.card("meal_logged", utcnow(), f"{_about(items).capitalize()} logged",
                  f"I expect a peak near {pred['predicted_peak_mg_dl']:.0f}. That's an estimate, and I'll grade it "
                  f"in two hours.", "rising", attachments={"meal": meal})
    u.cards.append(c)
    broadcaster.publish(uid, "card", c)
    broadcaster.publish(uid, "state", current_state(uid))
    return meal


def _find(uid: str, meal_id: str) -> dict:
    for m in store.get(uid).meals:
        if m["meal_id"] == meal_id:
            return m
    raise HTTPException(404, f"meal {meal_id} not found")


@router.post("/meals")
async def post_meal(body: dict, uid: str = Depends(user_id)):
    eaten_at = parse(body["eaten_at"]) if body.get("eaten_at") else utcnow()
    source = body.get("source", "manual")
    if source not in ("chat", "manual"):
        raise HTTPException(422, "source must be chat or manual")
    return create_meal(uid, _items(body.get("items", [])), eaten_at, source)


@router.patch("/meals/{meal_id}")
async def patch_meal(meal_id: str, body: dict, uid: str = Depends(user_id)):
    meal = _find(uid, meal_id)
    meal["items"] = _items(body.get("items", []))
    meal["totals"] = totals(meal["items"])
    store.get(uid).predictions.pop(meal["prediction_id"], None)
    meal["prediction_id"] = _predict(uid, _about(meal["items"]), parse(meal["eaten_at"]), meal["items"],
                                     meal_id)["prediction_id"]
    broadcaster.publish(uid, "state", current_state(uid))
    return meal


@router.delete("/meals/{meal_id}")
async def delete_meal(meal_id: str, uid: str = Depends(user_id)):
    meal = _find(uid, meal_id)
    u = store.get(uid)
    u.meals.remove(meal)
    u.predictions.pop(meal["prediction_id"], None)
    broadcaster.publish(uid, "state", current_state(uid))
    return {"deleted": True}


@router.get("/meals")
async def get_meals(uid: str = Depends(user_id), date: str | None = None):
    return {"meals": store.get(uid).meals}


@router.post("/meals/due/{due_id}/log")
async def log_due(due_id: str, uid: str = Depends(user_id)):
    text = DUE_MEALS.get(due_id)
    if text is None:
        raise HTTPException(404, f"due meal {due_id} not found")
    names = [n.strip() for n in text.replace(" with ", " and ").split(" and ")]
    meal = create_meal(uid, _items([{"name": n} for n in names]), utcnow(), "replay_due")
    store.get(uid).dismissed_due.add(due_id)
    return meal


@router.post("/simulate")
async def simulate(body: dict, uid: str = Depends(user_id)):
    items = _items(body.get("items", []))
    eat_at = parse(body["eat_at"]) if body.get("eat_at") else utcnow()
    subject = store.get(uid).following or uid
    carbs = totals(items)["carbs_g"]
    base = mock.forecast(subject, eat_at, bump=0)
    full = mock.forecast(subject, eat_at, bump=carbs * 0.9, bump_in_min=0)
    peak_pt = max(full, key=lambda p: p["glucose_mg_dl"])
    peak = peak_pt["glucose_mg_dl"]
    half = max(base, key=lambda p: p["glucose_mg_dl"])["glucose_mg_dl"] + (peak - max(p["glucose_mg_dl"] for p in base)) / 2
    high = store.get(uid).profile["high_line_mg_dl"]
    verdict = "go" if peak < high else "go_with_tweak" if half < high or peak - 14 < high else "wait"
    pred = _predict(uid, _about(items), eat_at, items, None)
    name = items[0]["name"] if len(items) == 1 else "that"
    return {"items": items, "eat_at": iso(eat_at), "baseline_curve": base, "with_food_curve": full,
            "peak_mg_dl": peak, "peak_at": peak_pt["t"], "verdict": verdict,
            "summary": f"With the {name} you'd likely peak near {peak:.0f}.",
            "alternatives": [{"label": "Half portion", "peak_mg_dl": round(half, 1)},
                             {"label": "Walk 10 minutes after", "peak_mg_dl": round(peak - 14, 1),
                              "effect_source": "literature"}],
            "method": "model", "prediction_id": pred["prediction_id"]}


@router.post("/vitals")
async def vitals(body: dict, uid: str = Depends(user_id)):
    samples = [s for s in body.get("samples", []) if s.get("type") == "steps" and s.get("value") is not None]
    store.get(uid).steps += int(sum(s["value"] for s in samples))
    return {"accepted": len(samples)}


@router.post("/events")
async def events(body: dict, uid: str = Depends(user_id)):
    u = store.get(uid)
    at = parse(body["at"]) if body.get("at") else utcnow()
    kind = body.get("type")
    if kind == "walk_started":
        u.walk_started_at = at
    elif kind == "walk_completed":
        started = u.walk_started_at or at - timedelta(minutes=10)
        minutes = max(1, round((at - started).total_seconds() / 60))
        steps = int(body.get("steps") or minutes * 105)
        cadence = round(steps / minutes)
        walk = {"started_at": iso(started), "ended_at": iso(at), "minutes": minutes, "steps": steps,
                "cadence_spm": cadence, "intensity": "moderate" if cadence >= 100 else "light",
                "forecast_peak_drop_mg_dl": 14.0 if minutes >= 10 else round(1.4 * minutes, 1),
                "effect_source": "literature"}
        u.walks.append(walk)
        u.walk_started_at, u.alert = None, None
        c = mock.card("walk_summary", utcnow(), "Nice walk", f"{minutes} minutes, {steps:,} steps, "
                      f"{walk['intensity']} pace. Effect source: literature.", "happy")
        u.cards.append(c)
        broadcaster.publish(uid, "card", c)
        broadcaster.publish(uid, "mood", {"mood": "happy"})
        broadcaster.publish(uid, "state", current_state(uid))
    else:
        raise HTTPException(422, "type must be walk_started or walk_completed")
    return {"ok": True}


@router.get("/walks/latest")
async def latest_walk(uid: str = Depends(user_id)):
    u = store.get(uid)
    if u.walks:
        return u.walks[-1]
    now = utcnow()
    return {"started_at": iso(now - timedelta(hours=3, minutes=11)), "ended_at": iso(now - timedelta(hours=3)),
            "minutes": 11, "steps": 1180, "cadence_spm": 107, "intensity": "moderate",
            "forecast_peak_drop_mg_dl": 14.0, "effect_source": "literature"}


__all__ = ["router", "create_meal", "config"]
