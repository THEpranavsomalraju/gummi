"""Per-teammate in-memory state (profile, follow, cards, steps, walks). Replay participants live in the engine."""
from dataclasses import dataclass, field

from .. import config
from ..util import display_name_for


@dataclass
class UserState:
    user_id: str
    profile: dict
    following: str | None = None
    meals: list[dict] = field(default_factory=list)       # teammate's own food-log entries (manual or added by Gummi)
    meal_sims: dict = field(default_factory=dict)         # meal_id -> simulation summary for entries not graded
    grades: list[dict] = field(default_factory=list)
    cards: list[dict] = field(default_factory=list)       # oldest first, unique card_id
    steps: int = 0
    walks: list[dict] = field(default_factory=list)
    overlay_walks: list[dict] = field(default_factory=list)   # phone walks placed on the replay timeline (D-28)
    walk_started_at: object = None
    walk_started_r: float | None = None
    alert: dict | None = None
    proud_until: float = 0.0
    happy_until: float = 0.0

    def add_card(self, card: dict) -> None:
        """CONTRACT 1.3 upsert: a card with a known card_id replaces the old one in place."""
        for i, c in enumerate(self.cards):
            if c["card_id"] == card["card_id"]:
                self.cards[i] = card
                return
        self.cards.append(card)
        if len(self.cards) > 300:
            del self.cards[:50]


class HotStore:
    def __init__(self):
        self.users: dict[str, UserState] = {}

    def get(self, user_id: str) -> UserState:
        if user_id not in self.users:
            self.users[user_id] = UserState(user_id, default_profile(user_id))
        return self.users[user_id]

    @staticmethod
    def display_name(user_id: str) -> str:
        return display_name_for(user_id)


def default_profile(user_id: str) -> dict:
    return {"user_id": user_id, "display_name": display_name_for(user_id), "high_line_mg_dl": config.HIGH_LINE,
            "low_line_mg_dl": config.LOW_LINE, "timezone": config.TIMEZONE, "onboarded": True}


def dexcom_status() -> dict:
    return {"connected": False, "environment": "sandbox", "data_through": None, "delay_minutes": config.DELAY_MINUTES,
            "last_sync": None, "last_error": None, "source": "replay", "ingest_mode": "status_only"}


store = HotStore()
