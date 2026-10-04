"""StoryCard construction (CONTRACT section 3). Cards upsert by card_id (1.3)."""
from datetime import datetime

from ..util import TZ, iso, new_id


def card(type_: str, created_at: datetime, title: str, body: str, mood: str, actions=None, attachments=None,
         generated_by: str = "template", card_id: str | None = None, trace_id: str | None = None) -> dict:
    return {"card_id": card_id or new_id("c"), "type": type_, "created_at": iso(created_at), "title": title,
            "body": body, "mood": mood, "attachments": attachments, "actions": actions or [],
            "trace_id": trace_id, "generated_by": generated_by}


def meal_label(when: datetime) -> str:
    h = when.astimezone(TZ).hour
    return "Breakfast" if 4 <= h < 11 else "Lunch" if 11 <= h < 15 else "Dinner" if 17 <= h < 22 else "Snack"
