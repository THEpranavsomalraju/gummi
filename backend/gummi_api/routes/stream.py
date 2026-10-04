"""Replay controls, fleet, fleet view, Dexcom status (CONTRACT section 4)."""
from pathlib import Path

from fastapi import APIRouter, Depends
import asyncio
import re

from fastapi.responses import HTMLResponse, RedirectResponse

from .. import config
from ..auth import user_id
from ..dexcom import client as dexcom
from ..errors import ApiError
from ..live.broadcaster import broadcaster
from ..engine.engine import engine
from ..state import session
from ..state.hot_store import store
from ..state.view import fleet, stream_status
from ..stream.producer import clock, parse_start
from .core import current_state

router = APIRouter()
WEB = Path(__file__).parents[1] / "web"


def _status() -> dict:
    return stream_status()


def _save_soon() -> None:
    asyncio.get_running_loop().run_in_executor(None, session.save)


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
    session.mark_start(start_r)
    _push_states()
    _save_soon()
    return _status()


@router.post("/stream/stop")
async def stream_stop():
    clock.stop()
    _push_states()
    _save_soon()
    return _status()


@router.post("/stream/pause")
async def stream_pause():
    clock.pause()
    _push_states()
    _save_soon()
    return _status()


@router.post("/stream/resume")
async def stream_resume():
    clock.resume()
    _push_states()
    _save_soon()
    return _status()


@router.post("/stream/speed")
async def stream_speed(body: dict):
    speed = body.get("speed")
    if not isinstance(speed, (int, float)) or not 0 < speed <= 600:
        raise ApiError(422, "invalid", "speed must be a number between 0 and 600")
    clock.set_speed(speed)
    _push_states()
    _save_soon()
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
async def dexcom_status_route(uid: str = Depends(user_id)):
    return dexcom.status(uid)


@router.get("/dexcom/connect", response_class=HTMLResponse)
async def dexcom_connect(user: str | None = None):
    """Laptop browser page (D-17). With ?user=u_name it goes straight to Dexcom's sandbox login."""
    if not dexcom.configured():
        return HTMLResponse(_page("Dexcom isn't set up yet", "The App is missing its Dexcom client id or secret."), 503)
    if user:
        if not re.match(r"^u_[a-z0-9_]{1,32}$", user):
            raise ApiError(400, "bad_request", "user must look like u_<name>")
        return RedirectResponse(dexcom.login_url(user), status_code=302)
    return HTMLResponse((WEB / "dexcom_connect.html").read_text())


@router.get("/dexcom/callback", response_class=HTMLResponse)
async def dexcom_callback(code: str | None = None, state: str | None = None, error: str | None = None):
    uid = dexcom.verify_state(state or "")
    if error or not code or not uid:
        return HTMLResponse(_page("Couldn't connect", f"Dexcom said: {error or 'missing code or state'}. Try again."), 400)
    try:
        await asyncio.to_thread(dexcom.exchange_code, uid, code)
    except Exception as e:  # noqa: BLE001
        return HTMLResponse(_page("Couldn't connect", f"The token exchange failed ({type(e).__name__}). Try again."), 502)
    d = dexcom.details(uid)
    egv = d.get("latest_egv") or {}
    for u in broadcaster.users():
        if u == uid:
            broadcaster.publish(u, "state", current_state(u))
    body = (f"{uid} is connected to the Dexcom sandbox. Data through {d.get('data_through') or 'n/a'}"
            + (f", newest sandbox reading {egv.get('value')} mg/dL." if egv else ".")
            + " Gummi shows connection status only; it never replaces your Dexcom app. You can close this tab.")
    return HTMLResponse(_page("Connected", body))


@router.post("/dexcom/disconnect")
async def dexcom_disconnect(uid: str = Depends(user_id)):
    dexcom.disconnect(uid)
    broadcaster.publish(uid, "state", current_state(uid))
    return {"ok": True}


def _page(title: str, body: str) -> str:
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" '
            f'content="width=device-width, initial-scale=1"><title>Gummi Dexcom</title><style>body{{font:18px/1.5 '
            f'-apple-system,system-ui,sans-serif;max-width:560px;margin:64px auto;padding:0 16px;color:#1d2433}}'
            f'p{{color:#4b5568}}</style></head><body><h1>{title}</h1><p>{body}</p></body></html>')
