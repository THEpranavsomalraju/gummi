"""Replay controls, fleet, fleet view, Dexcom status (CONTRACT section 4)."""
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse

from .. import config
from ..auth import user_id
from ..live.broadcaster import broadcaster
from ..mock import data as mock
from ..state.hot_store import dexcom_status, store
from ..stream.producer import clock
from ..util import display_name_for, iso, utcnow
from .core import current_state

router = APIRouter()
WEB = Path(__file__).parents[1] / "web"


def _status() -> dict:
    return clock.status(pipeline_lag_seconds=6.0 if clock.running else None)


def _push_states() -> None:
    """Pause, resume, speed and follow change upcoming_due and the anchor, so every connected phone gets fresh State."""
    for uid in broadcaster.users():
        broadcaster.publish(uid, "state", current_state(uid))


@router.post("/stream/start")
async def stream_start(body: dict | None = None):
    body = body or {}
    try:
        clock.start(body.get("speed", 60), body.get("delay_minutes", config.DELAY_MINUTES), body.get("start_at"))
    except ValueError as e:
        raise HTTPException(422, str(e))
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
        raise HTTPException(422, "speed must be a number between 0 and 600")
    clock.set_speed(speed)
    _push_states()
    return _status()


@router.get("/stream/status")
async def stream_status():
    return _status()


@router.get("/fleet")
async def fleet():
    now = utcnow()
    entries = []
    for pid in config.PARTICIPANTS:
        est = mock.estimate(pid, now)
        fc = mock.forecast(pid, now, bump=0)
        view = mock.gummi_view(pid, now, est)
        g, c, lv, n = mock.participant_accuracy(pid)
        entries.append({"user_id": pid, "display_name": display_name_for(pid),
                        "mood": mock.mood_for(view, est, fc, now), "data_through": iso(mock.data_through(now)),
                        "sparkline": mock.sparkline(pid, now), "grades": n, "gummi_mae_mg_dl": g,
                        "cgm_only_mae_mg_dl": c, "last_value_mae_mg_dl": lv, "last_grade": None})
    avg = lambda k: round(sum(e[k] for e in entries) / len(entries), 1)  # noqa: E731
    return {"entries": entries, "fleet_gummi_mae_mg_dl": avg("gummi_mae_mg_dl"),
            "fleet_cgm_only_mae_mg_dl": avg("cgm_only_mae_mg_dl"),
            "fleet_last_value_mae_mg_dl": avg("last_value_mae_mg_dl"), "stream": _status()}


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


__all__ = ["router", "store"]
