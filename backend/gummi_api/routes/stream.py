"""Replay controls, fleet, fleet view, Dexcom status (CONTRACT section 4)."""
from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse

from .. import config
from ..auth import user_id
from ..errors import ApiError
from ..live.broadcaster import broadcaster
from ..engine.engine import engine
from ..state.hot_store import dexcom_status, store
from ..state.view import fleet, stream_status
from ..stream.producer import clock, parse_start
from .core import current_state

router = APIRouter()
WEB = Path(__file__).parents[1] / "web"


def _status() -> dict:
    return stream_status()


def _push_states() -> None:
    """Pause, resume, speed and follow change upcoming_due and the anchor, so every connected phone gets fresh State."""
    for uid in broadcaster.users():
        broadcaster.publish(uid, "state", current_state(uid))


@router.post("/stream/start")
async def stream_start(body: dict | None = None):
    body = body or {}
    if not engine.ready:
        raise ApiError(503, "warming_up", engine.load_error or "Gummi is still loading the model and replay data")
    speed = body.get("speed", 60)
    if not isinstance(speed, (int, float)) or not 0 < speed <= 600:
        raise ApiError(422, "invalid", "speed must be a number between 0 and 600")
    try:
        start_r = parse_start(body.get("start_at") or config.DEFAULT_START)
    except ValueError as e:
        raise ApiError(422, "invalid", str(e))
    clock.start(speed, body.get("delay_minutes", config.DELAY_MINUTES), body.get("start_at") or config.DEFAULT_START)
    for u in store.users.values():
        u.cards, u.grades, u.alert, u.overlay_walks = [], [], None, []
    engine.start(start_r)
    _push_states()
    return _status()


@router.post("/stream/stop")
async def stream_stop():
    clock.stop()
    _push_states()
    return _status()


@router.post("/stream/pause")
async def stream_pause():
    clock.pause()
    _push_states()
    return _status()


@router.post("/stream/resume")
async def stream_resume():
    clock.resume()
    _push_states()
    return _status()


@router.post("/stream/speed")
async def stream_speed(body: dict):
    speed = body.get("speed")
    if not isinstance(speed, (int, float)) or not 0 < speed <= 600:
        raise ApiError(422, "invalid", "speed must be a number between 0 and 600")
    clock.set_speed(speed)
    _push_states()
    return _status()


@router.get("/stream/status")
async def stream_status_route():
    return _status()


@router.get("/fleet")
async def fleet_route():
    return fleet()


@router.get("/fleet/view", response_class=HTMLResponse)
async def fleet_view():
    return (WEB / "fleet.html").read_text()


@router.get("/dexcom/status")
async def dexcom(uid: str = Depends(user_id)):
    return dexcom_status()


@router.get("/dexcom/connect", response_class=HTMLResponse)
async def dexcom_connect():
    return (WEB / "dexcom_connect.html").read_text()


@router.get("/dexcom/callback", response_class=HTMLResponse)
async def dexcom_callback(code: str | None = None, state: str | None = None):
    return "<h1>Dexcom sandbox</h1><p>OAuth is not wired up yet (Phase 0 auth spike).</p>"


@router.post("/dexcom/disconnect")
async def dexcom_disconnect(uid: str = Depends(user_id)):
    return {"ok": True}


