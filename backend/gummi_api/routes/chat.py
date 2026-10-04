"""POST /chat as server-sent events (CONTRACT section 6). Scripted replies with real tool and card events until the LLM agent lands.

The routing mirrors the agent rules: past or present eating gets logged, food questions get simulated, anything else
gets Gummi's estimate. Phase 2 swaps the script for the D-04 LLM with tools and MLflow tracing.
"""
import asyncio
import re

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from ..auth import user_id
from ..live.broadcaster import sse
from ..state.hot_store import store
from ..util import display_name_for, new_id
from .core import counters, current_state
from ..errors import ApiError
from .meals import _items, create_meal, run_simulation

router = APIRouter()
ATE = re.compile(r"\b(i\s+(just\s+)?(had|ate)|i'm eating|i am eating|just had|for (breakfast|lunch|dinner))\b", re.I)
ASK = re.compile(r"\b(can i|should i|could i|what if i|is it ok)\b", re.I)
SPLIT = re.compile(r",|\band\b|\bwith\b|\bplus\b", re.I)
NUM = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "half": 0.5}


def parse_foods(text: str) -> list[dict]:
    text = re.sub(ATE.pattern + r"|" + ASK.pattern + r"|\b(eat|have|a|right now|now|today)\b(?=\s)", " ", text, flags=re.I)
    text = re.sub(r"[?.!]", "", text)
    out = []
    for part in SPLIT.split(text):
        words = part.strip().lower().split()
        if not words:
            continue
        qty = 1.0
        if words[0] in NUM or words[0].replace(".", "", 1).isdigit():
            qty = NUM.get(words[0]) or float(words[0])
            words = words[1:]
        if words:
            out.append({"name": " ".join(words), "quantity": qty})
    return out or [{"name": "snack", "quantity": 1}]


async def _tokens(text: str):
    for word in text.split(" "):
        yield sse("token", {"text": word + " "})
        await asyncio.sleep(0.03)


@router.post("/chat")
async def chat(body: dict, uid: str = Depends(user_id)):
    message = (body.get("message") or "").strip()
    conversation_id = body.get("conversation_id") or new_id("conv")
    counters["chat_turns"] += 1

    async def stream():
        yield sse("mood", {"mood": "thinking"})
        await asyncio.sleep(0.2)
        acting = store.get(uid).following
        if ASK.search(message) or (ATE.search(message) and acting):
            yield sse("tool", {"name": "simulate_food", "status": "start"})
            try:
                sim = run_simulation(uid, _items(parse_foods(message)))
            except ApiError as e:
                yield sse("tool", {"name": "simulate_food", "status": "end"})
                yield sse("error", {"code": e.code, "message": e.message})
                return
            yield sse("tool", {"name": "simulate_food", "status": "end"})
            yield sse("card", {"card_type": "simulation", "payload": sim})
            text = sim["summary"] + " " + {"go": "That stays under your line.",
                                           "go_with_tweak": "A half portion or a short walk after keeps it closer to your line.",
                                           "wait": "I'd wait, or pair it with a walk."}[sim["verdict"]]
            if ATE.search(message) and acting:
                text = f"I simulated that, since {display_name_for(acting)}'s real meals come from the study log. " + text
            mood = "calm" if sim["verdict"] == "go" else "rising"
        elif ATE.search(message):
            yield sse("tool", {"name": "log_meal", "status": "start"})
            meal = create_meal(uid, _items(parse_foods(message)), "chat")
            yield sse("tool", {"name": "log_meal", "status": "end"})
            yield sse("card", {"card_type": "meal_saved", "payload": meal})
            text = ("Logged it. You can edit the portions on the card. Follow a participant to see how meals move "
                    "real glucose and how my predictions grade.")
            mood = "calm"
        else:
            yield sse("tool", {"name": "get_state", "status": "start"})
            view = current_state(uid)["gummi_view"]
            yield sse("tool", {"name": "get_state", "status": "end"})
            if view:
                yield sse("card", {"card_type": "gummi_view", "payload": view})
                text = (f"Gummi's estimate right now is about {view['glucose_mg_dl']:.0f}, {view['trend'].replace('_', ' ')}. "
                        f"It's an estimate, not a reading. Check your Dexcom app for current readings.")
            else:
                text = "I don't have glucose data for you yet. Follow a participant to see Gummi's estimate."
            mood = "calm"
        async for tok in _tokens(text):
            yield tok
        yield sse("mood", {"mood": mood})
        trace_id = new_id("tr")
        counters["last_trace_id"] = trace_id
        yield sse("done", {"conversation_id": conversation_id, "trace_id": trace_id})

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
