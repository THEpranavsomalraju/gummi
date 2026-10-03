"""Phone routes: health, state, live, feed, predictions, grades, profile, follow, engine (CONTRACT section 4)."""
from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse

from .. import config
from ..auth import user_id
from ..errors import ApiError
from ..live.broadcaster import broadcaster, sse
from ..mock import data as mock
from ..state.hot_store import store
from ..stream.landing_writer import landing
from ..stream.producer import clock
from ..util import iso, utcnow

router = APIRouter()
counters = {"events": 0, "predictions": 0, "grades": 0, "agent_runs": 0, "chat_turns": 0, "last_trace_id": None}


def current_state(uid: str) -> dict:
    status = clock.status()
    s = store.state(uid, status)
    now = clock.now()
    s["replay_now"] = iso(clock.replay_to_wall(now)) if s["acting_as"] and clock.running and now is not None else None
    s["stream"] = status
    return s


@router.get("/health")
async def health():
    return {"status": "ok", "mode": config.MODE, "version": config.VERSION}


@router.get("/state")
async def get_state(uid: str = Depends(user_id)):
    return current_state(uid)


@router.get("/live")
async def live(uid: str = Depends(user_id), ping_seconds: float = Query(config.PING_SECONDS, ge=0.5, le=60.0)):
    first = [sse("state", current_state(uid))]
    return StreamingResponse(broadcaster.stream(uid, first, ping_seconds), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@router.get("/feed")
async def feed(uid: str = Depends(user_id), date: str | None = None):
    u = store.get(uid)
    cards = mock.day_cards(u.following or uid, utcnow()) + u.cards
    return {"cards": sorted(cards, key=lambda c: c["created_at"], reverse=True)}


@router.get("/predictions")
async def predictions(uid: str = Depends(user_id), status: str | None = Query(None, pattern="^(pending|graded)$")):
    preds = current_state(uid)["pending_predictions"] + [p for p in store.get(uid).predictions.values()
                                                          if p["status"] == "graded"]
    seen, out = set(), []
    for p in preds:
        if p["prediction_id"] not in seen and (status is None or p["status"] == status):
            seen.add(p["prediction_id"])
            out.append(p)
    return {"predictions": out}


@router.get("/grades")
async def grades(uid: str = Depends(user_id), date: str | None = None):
    u = store.get(uid)
    day = [c["attachments"]["grade"] for c in mock.day_cards(u.following or uid, utcnow())
           if c.get("attachments") and "grade" in c["attachments"]]
    return {"grades": day + u.grades}


@router.get("/profile")
async def get_profile(uid: str = Depends(user_id)):
    return store.get(uid).profile


@router.put("/profile")
async def put_profile(body: dict, uid: str = Depends(user_id)):
    p = store.get(uid).profile
    for k in ("display_name", "high_line_mg_dl", "low_line_mg_dl", "timezone", "onboarded"):
        if k in body:
            p[k] = body[k]
    broadcaster.publish(uid, "state", current_state(uid))
    return p


@router.post("/follow")
async def follow(body: dict, uid: str = Depends(user_id)):
    target = body.get("user_id")
    if target is not None and target not in config.PARTICIPANTS:
        raise ApiError(404, "not_found", f"unknown participant {target}")
    store.get(uid).following = target
    s = current_state(uid)
    broadcaster.publish(uid, "state", s)
    return s


@router.get("/engine")
async def engine():
    return {**counters, "events": clock.events_released, "live_connections": broadcaster.connections(),
            "landing": landing.status(), "mode": config.MODE}
