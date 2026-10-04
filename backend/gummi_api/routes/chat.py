"""POST /chat as server-sent events (CONTRACT section 6), backed by the agent in agent/chat.py."""
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from ..agent.chat import stream_turn
from ..auth import user_id
from ..errors import ApiError

router = APIRouter()


@router.post("/chat")
async def chat(body: dict, uid: str = Depends(user_id)):
    message = (body.get("message") or "").strip()
    if not message:
        raise ApiError(422, "invalid", "message must not be empty")
    if len(message) > 2000:
        raise ApiError(422, "invalid", "message is too long")
    return StreamingResponse(stream_turn(uid, message, body.get("conversation_id")), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
