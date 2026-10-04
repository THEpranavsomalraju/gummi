"""Time and id helpers shared by every module."""
import itertools
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from . import config

TZ = ZoneInfo(config.TIMEZONE)
_counter = itertools.count(1)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    """ISO 8601 with offset, in the profile timezone (CONTRACT section 1)."""
    return dt.astimezone(TZ).isoformat(timespec="seconds")


def iso_utc(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def parse(ts: str) -> datetime:
    dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def floor5(dt: datetime) -> datetime:
    return dt.replace(second=0, microsecond=0, minute=dt.minute - dt.minute % 5)


def new_id(prefix: str) -> str:
    return f"{prefix}_{next(_counter)}"


def r1(x: float) -> float:
    return round(float(x), 1)


def local_midnight(dt: datetime) -> datetime:
    local = dt.astimezone(TZ)
    return local.replace(hour=0, minute=0, second=0, microsecond=0)


def display_name_for(user_id: str) -> str:
    """p_003 -> Participant 3, u_mahil -> Mahil."""
    if user_id.startswith("p_") and user_id[2:].isdigit():
        return f"Participant {int(user_id[2:])}"
    return user_id.split("_", 1)[-1].title()


__all__ =["TZ", "utcnow", "iso", "iso_utc", "parse", "floor5", "new_id", "r1", "local_midnight", "timedelta"]
