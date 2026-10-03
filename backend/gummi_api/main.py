"""Gummi API: the single Databricks App behind the iPhone app (CONTRACT.md sections 4 to 7)."""
import asyncio
import contextlib
import logging
import random
from datetime import timedelta

from fastapi import APIRouter, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import config
from .errors import ApiError
from .live.broadcaster import broadcaster
from .mock import data as mock
from .routes import chat, core, meals, stream
from .state.hot_store import store
from .stream.landing_writer import landing
from .stream.producer import clock
from .util import utcnow

logging.basicConfig(level=logging.INFO)


async def mock_ticker() -> None:
    """Mock mode: fresh State every 5 s, a new card every MOCK_CARD_SECONDS, a grade and proud mood every third card."""
    i, last_card = 0, 0.0
    loop = asyncio.get_running_loop()
    while True:
        await asyncio.sleep(config.MOCK_STATE_SECONDS)
        users = broadcaster.users()
        for uid in users:
            broadcaster.publish(uid, "state", core.current_state(uid))
        if users and loop.time() - last_card >= config.MOCK_CARD_SECONDS:
            last_card, now = loop.time(), utcnow()
            for uid in users:
                u = store.get(uid)
                card = mock.rotating_card(i, now)
                u.cards.append(card)
                broadcaster.publish(uid, "card", card)
                if card["type"] == "walk_suggested":
                    u.alert = mock.walk_alert(now)
                    broadcaster.publish(uid, "alert", u.alert)
                if card["type"] == "grade":
                    g = mock.grade("pr_mock", "snack", now, random.Random(i))
                    u.grades.append(g)
                    u.proud_until = now + timedelta(seconds=20)
                    broadcaster.publish(uid, "grade", g)
                    broadcaster.publish(uid, "mood", {"mood": "proud"})
                    core.counters["grades"] += 1
            i += 1


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    tasks = [asyncio.create_task(landing.run()), asyncio.create_task(clock.run())]
    if config.MODE == "mock":
        tasks.append(asyncio.create_task(mock_ticker()))
    yield
    for t in tasks:
        t.cancel()
    with contextlib.suppress(Exception):
        await landing.flush()


app = FastAPI(title="Gummi API", version=config.VERSION, lifespan=lifespan)


@app.middleware("http")
async def mode_header(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Gummi-Mode"] = config.MODE
    return response


def _error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status,
                        headers={"X-Gummi-Mode": config.MODE})


@app.exception_handler(ApiError)
async def api_error(request: Request, exc: ApiError):
    return _error(exc.status, exc.code, exc.message)


@app.exception_handler(StarletteHTTPException)
async def http_error(request: Request, exc: StarletteHTTPException):
    codes = {400: "bad_request", 401: "unauthorized", 404: "not_found", 405: "method_not_allowed", 409: "conflict",
             422: "invalid", 429: "rate_limited"}
    return _error(exc.status_code, codes.get(exc.status_code, "error"), str(exc.detail))


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    first = exc.errors()[0] if exc.errors() else {}
    return _error(422, "invalid", f"{'.'.join(str(x) for x in first.get('loc', []))}: {first.get('msg', 'invalid request')}")


@app.exception_handler(Exception)
async def server_error(request: Request, exc: Exception):
    logging.exception("unhandled error on %s", request.url.path)
    return _error(500, "internal", "Something went wrong on Gummi's side. Try again.")


api = APIRouter(prefix="/api/v1")
for r in (core.router, meals.router, chat.router, stream.router):
    api.include_router(r)
app.include_router(api)
