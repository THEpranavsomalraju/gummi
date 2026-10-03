"""Per-user in-memory state. Phone routes read only from here (Phase 1: backed by mock generators)."""
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from .. import config
from ..mock import data as mock
from ..util import display_name_for, iso, utcnow


@dataclass
class UserState:
    user_id: str
    profile: dict
    following: str | None = None
    meals: list[dict] = field(default_factory=list)
    predictions: dict[str, dict] = field(default_factory=dict)
    grades: list[dict] = field(default_factory=list)
    cards: list[dict] = field(default_factory=list)          # pushed during this session, newest last
    steps: int = 0
    walks: list[dict] = field(default_factory=list)
    walk_started_at: datetime | None = None
    alert: dict | None = None
    proud_until: datetime | None = None
    dismissed_due: set[str] = field(default_factory=set)


class HotStore:
    def __init__(self):
        self.users: dict[str, UserState] = {}

    def get(self, user_id: str) -> UserState:
        if user_id not in self.users:
            self.users[user_id] = UserState(user_id, default_profile(user_id))
        return self.users[user_id]

    def state(self, user_id: str, stream_status: dict) -> dict:
        """Build a contract State for user_id at the current wall clock."""
        u = self.get(user_id)
        now = utcnow()
        subject = u.following or user_id                     # acting as the followed participant (D-27)
        conf = mock.confirmed(subject, now)
        est = mock.estimate(subject, now)
        fc = mock.forecast(subject, now)
        view = mock.gummi_view(subject, now, est)
        cards = mock.day_cards(subject, now) + u.cards
        today_conf = [p["glucose_mg_dl"] for p in conf]
        in_range = sum(config.LOW_LINE < g < config.HIGH_LINE for g in today_conf) / max(1, len(today_conf))
        acc = mock.participant_accuracy(subject)
        pending = [p for p in u.predictions.values() if p["status"] == "pending"]
        if not pending:
            last = conf[-1]["glucose_mg_dl"]
            pending = [mock.prediction("Breakfast, 2 waffles", now - timedelta(minutes=40), 158.0, last, fc[:12])]
        return {
            "user_id": user_id, "following": u.following, "acting_as": u.following,
            "dexcom": dexcom_status(),
            "gummi_view": view, "confirmed": conf, "estimate": est, "forecast": fc,
            "mood": mock.mood_for(view, est, fc, now, u.proud_until),
            "alert": u.alert, "top_card": cards[-1] if cards else None,
            "pending_predictions": pending,
            "today": {"time_in_range_pct": round(100 * in_range, 1), "peak_mg_dl": max(today_conf),
                      "meals": 2 + len(u.meals), "steps": 3120 + u.steps, "walks": 1 + len(u.walks),
                      "gummi_mae_mg_dl": acc[0], "cgm_only_mae_mg_dl": acc[1], "last_value_mae_mg_dl": acc[2]},
            "profile": {"high_line_mg_dl": u.profile["high_line_mg_dl"], "low_line_mg_dl": u.profile["low_line_mg_dl"]},
            "upcoming_due": mock.upcoming_due(now, u.following, stream_status["running"], stream_status["paused"]),
            "model_version": config.MODEL_VERSION, "server_time": iso(now),
        }


def default_profile(user_id: str) -> dict:
    return {"user_id": user_id, "display_name": display_name_for(user_id), "high_line_mg_dl": config.HIGH_LINE,
            "low_line_mg_dl": config.LOW_LINE, "timezone": config.TIMEZONE, "onboarded": True}


def dexcom_status() -> dict:
    return {"connected": False, "environment": "sandbox", "data_through": None, "delay_minutes": config.DELAY_MINUTES,
            "last_sync": None, "last_error": None, "source": "replay", "ingest_mode": "status_only"}


store = HotStore()
