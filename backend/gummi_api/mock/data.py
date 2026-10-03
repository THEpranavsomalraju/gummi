"""Mock mode data (Phase 1): realistic, deterministic curves relative to the wall clock.

Confirmed readings end an hour ago (the Dexcom delay), the estimate covers that hour with a widening band, and the
2-hour forecast carries a breakfast bump. Every number here is synthetic; X-Gummi-Mode: mock says so on every response.
"""
import hashlib
import math
import random
from datetime import datetime, timedelta

from .. import config
from ..util import TZ, display_name_for, floor5, iso, local_midnight, new_id, r1, utcnow

MEALS_LOCAL = ((7.5, 45.0), (12.75, 38.0), (18.5, 42.0))      # hour, rise in mg/dL


def _seed(user_id: str) -> int:
    return int(hashlib.md5(user_id.encode()).hexdigest()[:8], 16)


def _kernel(minutes: float, peak_min: float = 45.0) -> float:
    """Gamma-like meal response, 1.0 at peak_min."""
    if minutes <= 0:
        return 0.0
    x = minutes / peak_min
    return x * math.exp(1.0 - x)


def glucose_at(user_id: str, t: datetime) -> float:
    s = _seed(user_id)
    local = t.astimezone(TZ)
    h = local.hour + local.minute / 60
    g = 90 + (s % 18) + 5 * math.sin((h - 4) / 24 * 2 * math.pi)
    for day in (0, -1):
        for meal_h, rise in MEALS_LOCAL:
            meal_t = local_midnight(t) + timedelta(days=day, hours=meal_h)
            g += (rise + (s >> 4) % 15) * _kernel((t - meal_t).total_seconds() / 60)
    g += random.Random(s ^ int(t.timestamp() // 300)).gauss(0, 1.8)
    return r1(max(55.0, g))


def data_through(now: datetime) -> datetime:
    return floor5(now - timedelta(minutes=config.DELAY_MINUTES))


def confirmed(user_id: str, now: datetime, hours: float = 6) -> list[dict]:
    end = data_through(now)
    n = int(hours * 12)
    return [{"t": iso(t), "glucose_mg_dl": glucose_at(user_id, t), "kind": "confirmed"}
            for t in (end - timedelta(minutes=5 * k) for k in range(n, -1, -1))]


def estimate(user_id: str, now: datetime) -> list[dict]:
    start = data_through(now)
    out = []
    for k in range(1, 13):
        t = start + timedelta(minutes=5 * k)
        half = 4 + 0.28 * 5 * k
        g = glucose_at(user_id, t) + 0.05 * 5 * k
        out.append({"t": iso(t), "glucose_mg_dl": r1(g), "band_low_mg_dl": r1(g - half),
                    "band_high_mg_dl": r1(g + half), "kind": "estimate"})
    return out


def forecast(user_id: str, now: datetime, minutes: int = 120, bump: float = 32.0, bump_in_min: float = 20.0) -> list[dict]:
    start = floor5(now)
    out = []
    for k in range(1, minutes // 5 + 1):
        t = start + timedelta(minutes=5 * k)
        half = 20 + 0.12 * 5 * k
        g = glucose_at(user_id, t) + bump * _kernel(5 * k - bump_in_min)
        out.append({"t": iso(t), "glucose_mg_dl": r1(g), "band_low_mg_dl": r1(g - half),
                    "band_high_mg_dl": r1(g + half), "kind": "forecast"})
    return out


def gummi_view(user_id: str, now: datetime, est: list[dict]) -> dict:
    last, prev = est[-1], est[-4]
    slope = (last["glucose_mg_dl"] - prev["glucose_mg_dl"]) / 15.0
    trend = ("rising_fast" if slope > 2 else "rising" if slope > 1 else "falling_fast" if slope < -2
             else "falling" if slope < -1 else "flat")
    width = last["band_high_mg_dl"] - last["band_low_mg_dl"]
    return {"glucose_mg_dl": last["glucose_mg_dl"], "band_low_mg_dl": last["band_low_mg_dl"],
            "band_high_mg_dl": last["band_high_mg_dl"], "trend": trend, "as_of": iso(now),
            "minutes_since_confirmed": int((now - data_through(now)).total_seconds() // 60),
            "confidence": "high" if width < 25 else "medium" if width <= 45 else "low"}


def mood_for(view: dict, est: list[dict], fc: list[dict], now: datetime, proud_until: datetime | None = None) -> str:
    lows = [p["glucose_mg_dl"] for p in est + fc]
    if min(lows) <= config.LOW_LINE:
        return "low"
    if max(p["glucose_mg_dl"] for p in fc) >= config.HIGH_LINE:
        return "high"
    if proud_until and now < proud_until:
        return "proud"
    if view["trend"] == "falling_fast":
        return "dipping"
    if view["trend"] in ("rising", "rising_fast"):
        return "rising"
    if now.astimezone(TZ).hour >= 23 or now.astimezone(TZ).hour < 6:
        return "sleepy"
    return "calm"


# ---------- predictions, grades, cards ----------

def prediction(about: str, made_at: datetime, peak: float, last_value: float, curve: list[dict],
               meal_id: str | None = None, status: str = "pending", kind: str = "meal") -> dict:
    return {"prediction_id": new_id("pr"), "kind": kind, "made_at": iso(made_at), "about": about, "meal_id": meal_id,
            "window_start": iso(made_at), "window_end": iso(made_at + timedelta(hours=2)),
            "predicted_peak_mg_dl": r1(peak), "predicted_curve": curve,
            "cgm_only_peak_mg_dl": r1(last_value + (peak - last_value) * 0.45),
            "last_value_peak_mg_dl": r1(last_value), "status": status}


def grade(prediction_id: str, about: str, graded_at: datetime, rng: random.Random, walk_overlap: bool = False) -> dict:
    gummi = r1(rng.uniform(5, 11))
    cgm_only = r1(gummi + rng.uniform(1.5, 5))
    last_value = r1(cgm_only + rng.uniform(3, 8))
    predicted = int(rng.uniform(140, 175))
    actual = predicted + int(rng.uniform(-6, 6))
    message = (f"I predicted {predicted} for the {about}. It was {actual}. "
               f"CGM-only said {int(predicted - cgm_only * 2.2)}, last value said {int(predicted - last_value * 2.4)}.")
    if walk_overlap:
        message += " Walk effect not graded (replayed data)."
    return {"grade_id": new_id("g"), "prediction_id": prediction_id, "kind": "meal", "graded_at": iso(graded_at),
            "points": int(max(0, 30 - gummi)), "gummi_mae_mg_dl": gummi, "cgm_only_mae_mg_dl": cgm_only,
            "last_value_mae_mg_dl": last_value, "gummi_peak_error_mg_dl": r1(abs(actual - predicted)),
            "within_band_pct": r1(rng.uniform(78, 96)), "walk_effect_graded": not walk_overlap,
            "gummi_beats_cgm_only": gummi < cgm_only, "gummi_beats_last_value": gummi < last_value, "message": message}


def card(type_: str, created_at: datetime, title: str, body: str, mood: str, actions=None, attachments=None,
         generated_by: str = "template") -> dict:
    return {"card_id": new_id("c"), "type": type_, "created_at": iso(created_at), "title": title, "body": body,
            "mood": mood, "attachments": attachments, "actions": actions or [],
            "trace_id": new_id("tr") if generated_by == "agent" else None, "generated_by": generated_by}


def day_cards(user_id: str, now: datetime) -> list[dict]:
    """The day so far as story cards, oldest first, only those before now."""
    rng = random.Random(_seed(user_id) ^ now.toordinal())
    m = local_midnight(now)
    at = lambda h, mi=0: m + timedelta(hours=h, minutes=mi)  # noqa: E731
    g = grade("pr_breakfast", "waffles", at(9, 40), rng)
    deck = [
        card("morning_briefing", at(6, 5), "Good morning", "Overnight stayed between 88 and 112. Breakfast is your "
             "biggest rise most days, so I'll watch that one.", "calm", generated_by="agent"),
        card("meal_due", at(7, 30), "Breakfast time for Participant 12", "Two waffles with syrup and a black coffee",
             "calm", actions=[{"label": "Log it", "kind": "log_due_meal", "due_id": "d_1"}]),
        card("meal_logged", at(7, 32), "Waffles logged", "I expect a peak near 158 around 8:20. Your estimate band is "
             "wide this early, so treat it as likely, not certain.", "rising", generated_by="agent"),
        card("walk_suggested", at(7, 50), "A short walk could help", "Your forecast likely crosses 140 in about 30 "
             "minutes. A 10 minute walk after eating lowers peaks by about 14 mg/dL (literature).", "high",
             generated_by="agent"),
        card("walk_summary", at(8, 5), "Nice walk", "11 minutes, 1,180 steps, moderate pace. Effect source: literature.",
             "happy"),
        card("meal_story", at(9, 40), "Your waffles, two hours later", "Peak 161 at 8:25. I said 158. CGM-only said "
             "139, last value said 118.", "proud", attachments={"grade": g}, generated_by="agent",
             actions=[{"label": "Ask Gummi why", "kind": "open_chat", "prompt": "Why did I peak at 161?"}]),
        card("meal_due", at(12, 40), "Lunch time for Participant 12", "Turkey sandwich and an apple", "calm",
             actions=[{"label": "Log it", "kind": "log_due_meal", "due_id": "d_2"}]),
        card("evening_recap", at(20, 0), "Your day", "Three meals, two predictions graded, both closer than CGM-only. "
             "Lesson: breakfast rises most. Tomorrow: try the walk before the waffles, not after.", "calm",
             generated_by="agent"),
    ]
    return [c for c in deck if c["created_at"] <= iso(now)]


ROTATING = [
    ("grade", "Prediction graded", "Gummi within 7 mg/dL, CGM-only within 11, last value within 18.", "proud"),
    ("prediction", "New prediction", "Your snack likely peaks near 132 in about 45 minutes.", "rising"),
    ("walk_suggested", "Walk now?", "Forecast likely tops 140 within the hour. A 10 minute walk helps (literature).", "high"),
    ("meal_story", "Lunch, two hours later", "Peak 149 at 1:35 PM. I predicted 152.", "proud"),
    ("dexcom_status", "Dexcom sandbox", "Status only: connected to the sandbox, data through 11:00.", "calm"),
]


def rotating_card(i: int, now: datetime) -> dict:
    t, title, body, mood = ROTATING[i % len(ROTATING)]
    return card(t, now, title, body, mood, generated_by="template")


def walk_alert(now: datetime) -> dict:
    return {"alert_id": new_id("al"), "type": "walk_suggested",
            "message": "Your forecast likely crosses 140 soon. A 10 minute walk now helps (literature).",
            "created_at": iso(now), "expires_at": iso(now + timedelta(minutes=30)),
            "action": {"label": "Start walk", "kind": "start_walk", "minutes": 10}}


def sparkline(user_id: str, now: datetime) -> list[dict]:
    return confirmed(user_id, now, hours=3)[::3]


def participant_accuracy(user_id: str) -> tuple[float, float, float, int]:
    rng = random.Random(_seed(user_id))
    gummi = r1(rng.uniform(6.5, 11))
    return gummi, r1(gummi + rng.uniform(1, 4)), r1(gummi + rng.uniform(5, 9)), rng.randint(6, 22)


def upcoming_due(now: datetime, acting_as: str | None, running: bool, paused: bool) -> list[dict]:
    if not acting_as or not running or paused:
        return []
    name = display_name_for(acting_as)
    return [{"due_id": "d_3", "due_at": iso(now + timedelta(minutes=9)), "title": f"Snack time for {name}",
             "body": "Greek yogurt with honey"},
            {"due_id": "d_4", "due_at": iso(now + timedelta(minutes=31)), "title": f"Dinner time for {name}",
             "body": "Chicken stir fry with rice"}]


__all__ = ["glucose_at", "confirmed", "estimate", "forecast", "gummi_view", "mood_for", "prediction", "grade",
           "card", "day_cards", "rotating_card", "walk_alert", "sparkline", "participant_accuracy",
           "upcoming_due", "data_through", "datetime", "utcnow"]
