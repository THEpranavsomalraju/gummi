"""Gummi API: the single Databricks App behind the iPhone app (CONTRACT.md sections 4 to 7)."""
import asyncio
import contextlib
import logging
import time

from fastapi import APIRouter, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import config
from .errors import ApiError
from .engine.engine import engine
from .engine.gold import gold
from .live.broadcaster import broadcaster
from .routes import chat, core, meals, stream, system_map
from .state.hot_store import store
from .state.view import build_state
from .stream.landing_writer import landing
from .stream.producer import clock, parse_start

logging.basicConfig(level=logging.INFO)


async def engine_loop() -> None:
    """Load the model and replay tables off the event loop, prepare a still snapshot at the default start (so the phone
    has a chart before anyone presses start), then tick once per second and push State to every connected phone."""
    broadcaster.bind(asyncio.get_running_loop())
    await asyncio.to_thread(engine.load)
    from .agent import events
    from .agent.llm import warm
    events.start_workers(2)
    from .agent import reviewer
    reviewer.start()
    asyncio.get_running_loop().run_in_executor(None, warm)     # first chat turn skips connection setup
    if engine.ready and clock.anchor_replay is None:
        start_r = parse_start(config.DEFAULT_START)
        clock.anchor_replay, clock.anchor_wall = start_r, time.time()
        clock.start_day = int(start_r // 1440) + 1
        engine.start(start_r)
    last_push = 0.0
    seen: dict[str, int] = {}
    while True:
        await asyncio.sleep(1.0)
        try:
            await asyncio.to_thread(engine.tick)      # off the event loop: requests never wait on the model
        except Exception:  # noqa: BLE001
            logging.exception("engine tick failed")
        now = time.monotonic()
        for uid in broadcaster.users():
            pid = store.get(uid).following
            v = engine.subjects[pid].version if pid in engine.subjects else -1
            # at most once per second; on change, or every 5 s so Gummi's estimate keeps moving with the clock
            if seen.get(uid) != v or now - last_push >= 5:
                seen[uid] = v
                try:
                    broadcaster.publish(uid, "state", build_state(uid))
                except Exception:  # noqa: BLE001
                    logging.exception("state push failed for %s", uid)
        if now - last_push >= 5:
            last_push = now


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    tasks = [asyncio.create_task(landing.run()), asyncio.create_task(engine_loop()), asyncio.create_task(gold.run())]
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
for r in (core.router, meals.router, chat.router, stream.router, system_map.router):
    api.include_router(r)
app.include_router(api)
