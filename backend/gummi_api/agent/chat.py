"""The chat agent (CONTRACT sections 6 and 7): gpt-oss-120b with Gummi's tools, streamed as server-sent events.

The blocking LLM stream runs in a worker thread and hands events to the request through a queue, so one slow model
call never blocks other phones. Up to 6 tool steps per turn. Every turn is one MLflow trace (root span, one span per
LLM step and per tool) in the agent-traces experiment; its id goes back to the phone in the done event.
"""
import asyncio
import json
import logging
import threading
import time

from .. import activity, config
from ..live.broadcaster import sse
from ..state.hot_store import store
from ..util import new_id
from . import guard, reviewer, tools
from .llm import client
from .prompts import system_prompt

log = logging.getLogger("gummi.chat")
MAX_STEPS = 6
HISTORY_TURNS = 6
CONVERSATIONS: dict[str, list[dict]] = {}
_busy: set[str] = set()

try:
    import mlflow
    mlflow.set_tracking_uri("databricks")
    mlflow.set_experiment(experiment_id=config.MLFLOW_EXPERIMENT_ID)
    TRACING = True
except Exception as e:  # noqa: BLE001 (tracing is never allowed to break chat)
    log.warning("MLflow tracing off: %s", e)
    TRACING = False


class _NoSpan:
    trace_id = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def set_inputs(self, *_):
        pass

    def set_outputs(self, *_):
        pass

    def set_attributes(self, *_):
        pass


def span(name: str, kind: str):
    if not TRACING:
        return _NoSpan()
    try:
        return mlflow.start_span(name=name, span_type=kind)
    except Exception:  # noqa: BLE001
        return _NoSpan()


def _text_of(content) -> str:
    """gpt-oss streams content as a string or a list of parts; only "text" parts are for the user (no reasoning)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
    return ""


def _llm_step(messages: list[dict], emit, use_tools: bool = True) -> tuple[str, list[dict]]:
    last_err = None
    for model in (config.LLM_ENDPOINT, *config.LLM_FALLBACKS):
        text, calls, started = "", {}, False
        try:
            kwargs = {"reasoning_effort": "low"} if "gpt-oss" in model else {}
            # fail fast on a rate limit and switch models, instead of the client's silent retry with backoff
            stream = client().with_options(max_retries=0).chat.completions.create(
                model=model, messages=messages, stream=True, max_tokens=700, temperature=0.7,
                **({"tools": tools.CHAT_TOOLS, "tool_choice": "auto"} if use_tools else {}), **kwargs)
            for ch in stream:
                if not ch.choices:
                    continue
                d = ch.choices[0].delta
                piece = _text_of(d.content)
                if piece:
                    started = True
                    text += piece
                    emit("token", {"text": piece})
                for tc in d.tool_calls or []:
                    started = True
                    c = calls.setdefault(tc.index, {"id": tc.id or f"call_{tc.index}", "name": "", "args": ""})
                    if tc.id:
                        c["id"] = tc.id
                    if tc.function and tc.function.name:
                        c["name"] += tc.function.name
                    if tc.function and tc.function.arguments:
                        c["args"] += tc.function.arguments
            return text, [calls[i] for i in sorted(calls)]
        except Exception as e:  # noqa: BLE001
            last_err = e
            log.warning("LLM %s failed: %s", model, str(e)[:200])
            activity.hit("llm.fallback", detail=f"{model}: {str(e)[:80]}", log=True)
            if started:
                break                      # tokens already shown: don't replay the answer from another model
    raise RuntimeError(f"llm_unavailable: {last_err}")


def _mood_after(cards: list[dict]) -> str:
    for c in cards:
        if c["card_type"] == "simulation":
            return {"go": "calm", "go_with_tweak": "rising", "wait": "high"}.get(c["payload"].get("verdict"), "calm")
        if c["card_type"] == "walk_suggestion":
            return "rising"
    return "calm"


def run_turn(uid: str, message: str, conversation_id: str, emit) -> None:
    ctx = tools.Ctx(uid)
    u = store.get(uid)
    from ..stream.producer import clock
    now = clock.replay_to_wall(clock.now()) if ctx.subject is not None and clock.now() is not None else None
    sysmsg = system_prompt(u.profile["display_name"], ctx.pid if ctx.subject is not None else None,
                           now.strftime("%-I:%M %p") if now else None, u.profile["high_line_mg_dl"], u.profile["low_line_mg_dl"])
    history = CONVERSATIONS.get(conversation_id, [])[-2 * HISTORY_TURNS:]
    messages = [{"role": "system", "content": sysmsg}, *history, {"role": "user", "content": message}]
    cards: list[dict] = []
    final = ""
    tool_results: list = []
    quiet = lambda ev, data: None  # noqa: E731  (answers are checked before the phone sees them)
    t0 = time.perf_counter()
    with span("gummi_chat_turn", "AGENT") as root:
        root.set_inputs({"user_id": uid, "acting_as": ctx.pid, "message": message})
        for step in range(MAX_STEPS + 1):
            with span(f"llm_step_{step + 1}", "CHAT_MODEL") as s:
                s.set_inputs({"messages": len(messages), "last": messages[-1].get("content") if isinstance(messages[-1].get("content"), str) else None})
                text, calls = _llm_step(messages, quiet, use_tools=step < MAX_STEPS)
                s.set_outputs({"text": text, "tool_calls": [{"name": c["name"], "args": c["args"]} for c in calls]})
            final = text
            if not calls:
                break
            messages.append({"role": "assistant", "content": text or None,
                             "tool_calls": [{"id": c["id"], "type": "function",
                                             "function": {"name": c["name"], "arguments": c["args"] or "{}"}} for c in calls]})
            for c in calls:
                emit("tool", {"name": c["name"], "status": "start"})
                try:
                    args = json.loads(c["args"] or "{}")
                except json.JSONDecodeError:
                    args = {}
                with span(f"tool_{c['name']}", "TOOL") as ts:
                    ts.set_inputs(args)
                    res, card = tools.run(c["name"], args, ctx)
                    ts.set_outputs(res)
                activity.hit(f"tool.{c['name']}", detail="Coach agent", log=True)
                emit("tool", {"name": c["name"], "status": "end"})
                if card:
                    cards.append(card)
                    emit("card", card)
                messages.append({"role": "tool", "tool_call_id": c["id"], "content": tools.dumps(res)})
                tool_results.append(res)
        issues = guard.problems(message, final, guard.numbers_in(tool_results), u.profile["high_line_mg_dl"],
                                u.profile["low_line_mg_dl"])
        if issues:
            with span("self_check_rewrite", "CHAIN") as fix:
                fix.set_inputs({"draft": final, "problems": issues})
                messages += [{"role": "assistant", "content": final},
                             {"role": "user", "content": "Self-check before sending: your draft broke these rules: "
                              + "; ".join(issues) + ". Rewrite it so it follows every rule, same voice. Reply with the rewrite only."}]
                final, _ = _llm_step(messages, quiet, use_tools=False)
                fix.set_outputs({"rewrite": final})
            activity.hit("agent.self_check", detail=issues[0], log=True)
        for i in range(0, len(final), 24):                 # stream the checked answer
            emit("token", {"text": final[i:i + 24]})
        root.set_outputs({"text": final, "cards": [c["card_type"] for c in cards], "self_check": issues})
        root.set_attributes({"latency_ms": round((time.perf_counter() - t0) * 1000), "model": config.LLM_ENDPOINT})
        trace_id = getattr(root, "trace_id", None) or getattr(root, "request_id", None)
    CONVERSATIONS[conversation_id] = [*history, {"role": "user", "content": message},
                                      {"role": "assistant", "content": final}]
    activity.hit("agent.coach", detail=message[:60], trace_id=trace_id, log=True)
    reviewer.submit({"trace_id": trace_id, "message": message, "answer": final, "tool_results": tool_results})
    emit("mood", {"mood": _mood_after(cards)})
    emit("done", {"conversation_id": conversation_id, "trace_id": trace_id})
    from ..routes.core import counters
    counters["chat_turns"] += 1
    counters["last_trace_id"] = trace_id


async def stream_turn(uid: str, message: str, conversation_id: str | None):
    conversation_id = conversation_id or new_id("conv")
    loop = asyncio.get_running_loop()
    q: asyncio.Queue = asyncio.Queue()

    def emit(event: str, data) -> None:
        loop.call_soon_threadsafe(q.put_nowait, sse(event, data))

    if uid in _busy:
        yield sse("error", {"code": "rate_limited", "message": "One message at a time, please."})
        return
    _busy.add(uid)
    yield sse("mood", {"mood": "thinking"})

    def work():
        try:
            run_turn(uid, message, conversation_id, emit)
        except Exception as e:  # noqa: BLE001
            log.exception("chat turn failed")
            code = "llm_unavailable" if "llm_unavailable" in str(e) else "internal"
            emit("token", {"text": "Sorry, I lost my train of thought there. Try me again in a moment."})
            view = tools.run("get_state", {}, tools.Ctx(uid))[1]
            if view:
                emit("card", view)
            emit("error", {"code": code, "message": "The coach is unavailable right now."})
            emit("done", {"conversation_id": conversation_id, "trace_id": None})
        finally:
            loop.call_soon_threadsafe(q.put_nowait, None)

    threading.Thread(target=work, daemon=True, name=f"chat-{uid}").start()
    try:
        while True:
            item = await q.get()
            if item is None:
                break
            yield item
    finally:
        _busy.discard(uid)
