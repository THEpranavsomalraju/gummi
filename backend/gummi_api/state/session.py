"""Replay session that survives a redeploy (rehydration): the clock, speed and who follows whom, saved to the App's
Unity Catalog volume; on startup the engine fast-forwards silently to where it was.

Silent means no landing events (the pipeline already has them), no agent runs and no pushes; follower cards come
back as templates. A demo that restarts mid-day resumes at the same replay minute with its meals, predictions and
grades intact.
"""
import io
import json
import logging
import time
from datetime import datetime

from .. import config
from ..stream.producer import clock
from .hot_store import store

log = logging.getLogger("gummi.session")
PATH = f"/Volumes/{config.CATALOG}/gummi_data/landing/agent_memory/session.json"
_session_start: float | None = None
OUTAGE_PAUSE_S = 300


def mark_start(start_r: float) -> None:
    global _session_start
    _session_start = start_r


def snapshot() -> dict:
    return {"saved_at": time.time(), "session_start_r": _session_start, "running": clock.running, "paused": clock.paused,
            "speed": clock.speed, "delay_minutes": clock.delay_minutes, "start_day": clock.start_day,
            "demo_midnight": clock.demo_midnight.isoformat(), "anchor_replay": clock.anchor_replay,
            "anchor_wall": clock.anchor_wall,
            "users": {u.user_id: {"following": u.following, "profile": u.profile} for u in store.users.values()}}


def save() -> None:
    if not config.PERSIST:
        return
    try:
        from databricks.sdk import WorkspaceClient
        WorkspaceClient().files.upload(PATH, io.BytesIO(json.dumps(snapshot()).encode()), overwrite=True)
    except Exception as e:  # noqa: BLE001
        log.warning("session not saved: %s", str(e)[:160])


def load() -> dict | None:
    if not config.PERSIST:
        return None
    try:
        from databricks.sdk import WorkspaceClient
        return json.loads(WorkspaceClient().files.download(PATH).contents.read())
    except Exception as e:  # noqa: BLE001 (first run: nothing saved yet)
        log.info("no saved session (%s)", str(e)[:80])
        return None


def restore(engine) -> bool:
    """Rebuild the saved session. Returns True when a session was restored."""
    s = load()
    if not s or s.get("session_start_r") is None or s.get("anchor_replay") is None:
        return False
    for uid, u in (s.get("users") or {}).items():
        st = store.get(uid)
        st.following, st.profile = u.get("following"), u.get("profile") or st.profile
    clock.demo_midnight = datetime.fromisoformat(s["demo_midnight"])
    clock.start_day = int(s["start_day"])
    clock.speed, clock.delay_minutes = float(s["speed"]), int(s["delay_minutes"])
    # A quick redeploy resumes where it was; after a longer outage (the App stopped for quota) only the time the App
    # was alive counts, and the replay comes back paused instead of fast-forwarding past the end of the data.
    outage = time.time() - s.get("saved_at", time.time())
    paused = bool(s["paused"]) or outage > OUTAGE_PAUSE_S
    end_wall = s.get("saved_at", time.time()) if outage > OUTAGE_PAUSE_S else time.time()
    elapsed = max(0.0, end_wall - s["anchor_wall"]) * clock.speed / 60.0 if s["running"] and not s["paused"] else 0.0
    target = s["anchor_replay"] + elapsed
    t0 = time.time()
    engine.catch_up(s["session_start_r"], target)
    mark_start(s["session_start_r"])
    clock.anchor_replay, clock.anchor_wall = target, time.time()
    clock.running, clock.paused = bool(s["running"]), paused
    log.info("restored replay session at %.0f replay min (%d users) in %.1f s", target, len(s.get("users") or {}),
             time.time() - t0)
    return True
