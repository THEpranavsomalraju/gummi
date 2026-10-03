"""Gummi API: the single Databricks App behind the iPhone app (CONTRACT.md sections 4 to 7)."""
import asyncio
import json
import os
from datetime import datetime, timezone

from fastapi import APIRouter, FastAPI, Query, Request
from fastapi.responses import StreamingResponse

VERSION = "0.0.1"
MODE = os.environ.get("GUMMI_MODE", "mock")

app = FastAPI(title="Gummi API", version=VERSION)
api = APIRouter(prefix="/api/v1")


@app.middleware("http")
async def mode_header(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Gummi-Mode"] = MODE
    return response


@api.get("/health")
async def health():
    return {"status": "ok", "mode": MODE, "version": VERSION}


@api.get("/live")
async def live(ping_seconds: float = Query(15.0, ge=0.5, le=60.0)):
    """Server-sent events (CONTRACT section 5). Phase 0: pings only, to prove the Apps proxy does not buffer."""
    async def stream():
        yield ": connected\n\n"
        while True:
            yield f"event: ping\ndata: {json.dumps({'t': datetime.now(timezone.utc).isoformat()})}\n\n"
            await asyncio.sleep(ping_seconds)

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


app.include_router(api)
