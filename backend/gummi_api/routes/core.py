"""Phone routes: health, state, live, feed, predictions, grades, profile, follow, engine (CONTRACT section 4)."""
from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse

from .. import config
from ..auth import user_id
from ..engine.engine import engine
from ..engine.gold import gold
from ..errors import ApiError
from ..live.broadcaster import broadcaster, sse
from ..state.hot_store import store
from ..state.view import build_state
from ..stream.landing_writer import landing
from ..stream.producer import clock

router = APIRouter()
counters = {"agent_runs": 0, "chat_turns": 0, "last_trace_id": None}


def current_state(uid: str) -> dict:
    return build_state(uid)


def push_state(uid: str) -> None:
    broadcaster.publish(uid, "state", build_state(uid))


@router.get("/health")
async def health():
    status = "ok" if engine.ready else ("error" if engine.load_error else "warming_up")
    return {"status": status, "mode": config.MODE, "version": config.VERSION}


@router.get("/state")
async def get_state(uid: str = Depends(user_id)):
    return build_state(uid)


@router.get("/live")
async def live(uid: str = Depends(user_id), ping_seconds: float = Query(config.PING_SECONDS, ge=0.5, le=60.0)):
    first = [sse("state", build_state(uid))]
    return StreamingResponse(broadcaster.stream(uid, first, ping_seconds), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@router.get("/feed")
async def feed(uid: str = Depends(user_id), date: str | None = None):
    cards = store.get(uid).cards
    if date:
        cards = [c for c in cards if c["created_at"][:10] == date]
    return {"cards": sorted(cards, key=lambda c: c["created_at"], reverse=True)}


def _subject(uid: str):
    pid = store.get(uid).following
    return engine.subjects.get(pid) if pid else None


@router.get("/predictions")
async def predictions(uid: str = Depends(user_id), status: str | None = Query(None, pattern="^(pending|graded)$")):
    s = _subject(uid)
    preds = [engine.public_prediction(p) for p in (list(s.predictions.values()) if s else [])
             if status is None or p["status"] == status]
    return {"predictions": preds[-100:]}


@router.get("/grades")
async def grades(uid: str = Depends(user_id), date: str | None = None):
    s = _subject(uid)
    gs = list(s.grades) if s else list(store.get(uid).grades)
    if date:
        gs = [g for g in gs if g["graded_at"][:10] == date]
    return {"grades": gs[-200:]}


@router.get("/profile")
async def get_profile(uid: str = Depends(user_id)):
    return store.get(uid).profile


@router.put("/profile")
async def put_profile(body: dict, uid: str = Depends(user_id)):
    p = store.get(uid).profile
    for k in ("display_name", "high_line_mg_dl", "low_line_mg_dl", "timezone", "onboarded"):
        if k in body:
            p[k] = body[k]
    push_state(uid)
    return p


@router.post("/follow")
async def follow(body: dict, uid: str = Depends(user_id)):
    target = body.get("user_id")
    if target is not None and target not in config.PARTICIPANTS:
        raise ApiError(404, "not_found", f"unknown participant {target}")
    u = store.get(uid)
    if target != u.following:
        u.following, u.alert, u.overlay_walks = target, None, []
    s = build_state(uid)
    broadcaster.publish(uid, "state", s)
    return s


@router.get("/engine")
async def engine_status():
    return {**counters, **engine.counters, "ready": engine.ready, "load_error": engine.load_error,
            "model_version": engine.model.version if engine.model else None,
            "events": clock.events_released, "live_connections": broadcaster.connections(),
            "landing": landing.status(), "gold": gold.status(), "mode": config.MODE}
