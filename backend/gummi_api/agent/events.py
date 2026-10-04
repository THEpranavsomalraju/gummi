"""Event-driven agents (CONTRACT section 7): named agents that act on their own when something happens.

The engine posts a template card at once (the phone never waits), then hands the job to the agent that owns it. The
agent reasons with its own tools on the D-04 model and rewrites the same card (CONTRACT 1.3 upsert by card_id), with
generated_by "agent" and its MLflow trace id. A per-minute budget (D-22) keeps template cards when it runs out.

  Morning Briefing agent  first reading after 06:00      get_state, get_history, today_summary
  Meal Story agent        a meal's 2-hour window graded  explain_spike, get_history
  Walk Coach agent        forecast crosses the high line suggest_walk, get_state
  Evening Recap agent     20:00                          today_summary, get_gold_summary (required), get_history
"""
import json
import logging
import queue
import threading
import time

from .. import activity, config
from ..live.broadcaster import broadcaster
from ..state.hot_store import store
from ..stream.landing_writer import landing
from ..util import iso_utc, utcnow
from . import tools
from .chat import span
from .llm import client
from .prompts import RULES, SOUL

log = logging.getLogger("gummi.events")
BUDGET_PER_MIN = 12
MAX_STEPS = 4

AGENTS = {
    "morning_briefing": {
        "name": "Morning Briefing agent", "tools": ["get_state", "get_history", "today_summary"],
        "task": "Write this person's morning briefing: how the night went (from get_history), where you estimate "
                "they likely are now, and the one thing worth watching today. Use the tools first."},
    "meal_story": {
        "name": "Meal Story agent", "tools": ["explain_spike", "get_history"],
        "task": "Two hours after a meal, tell its story: what they ate, the real peak, and how your prediction "
                "compared with CGM-only and last value (all in the grade below). Own it when you were off. Add one useful observation, such as "
                "carbs, timing, or a walk. If the grade says the walk effect was not graded, say so."},
    "walk_coach": {
        "name": "Walk Coach agent", "tools": ["suggest_walk", "get_state"],
        "task": "Your forecast says they'll likely cross the high line soon. Call suggest_walk, then nudge a walk now: when "
                "the peak likely lands, how much a 10-minute walk could lower it, and the effect's source."},
    "evening_recap": {
        "name": "Evening Recap agent", "tools": ["today_summary", "get_gold_summary", "get_history"],
        "task": "Write the evening recap. You must call get_gold_summary for predicted versus actual from the "
                "Databricks gold tables (with CGM-only and last value), and today_summary. Give one lesson from "
                "today and one small experiment for tomorrow."},
}

_jobs: queue.Queue = queue.Queue(maxsize=200)
_runs: list[float] = []
_lock = threading.Lock()
counters = {"agent_runs": 0, "agent_fallbacks": 0, "agent_failures": 0}


def submit(agent: str, uid: str, card: dict, context: dict) -> None:
    """Called by the engine (any thread). The template card is already on the phone; the agent upgrades it."""
    try:
        _jobs.put_nowait({"agent": agent, "uid": uid, "card": card, "context": context})
    except queue.Full:
        counters["agent_fallbacks"] += 1


def _budget_ok() -> bool:
    now = time.time()
    with _lock:
        _runs[:] = [t for t in _runs if now - t < 60]
        if len(_runs) >= BUDGET_PER_MIN:
            return False
        _runs.append(now)
        return True


def _system(spec: dict) -> str:
    return (f"{SOUL}\n\n{RULES}\n\nYou are Gummi, working as the {spec['name']}. {spec['task']}\n"
            "Reply with JSON only: {\"title\": \"at most 6 words\", \"body\": \"at most 2 short sentences\"}.")


def _parse(text: str) -> dict | None:
    text = text.strip()
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        out = json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None
    if isinstance(out, dict) and out.get("body"):
        return {"title": str(out.get("title") or "").strip()[:60], "body": str(out["body"]).strip()[:400]}
    return None


def _complete(messages: list[dict], tool_list):
    """Background agents use their own endpoint so they never eat the phone chat's rate limit (Free Edition has a
    per-workspace QPS cap per endpoint). On 429: back off, then try the chat endpoint once."""
    last = None
    for attempt, model in enumerate((config.AGENT_ENDPOINT, config.AGENT_ENDPOINT, config.AGENT_ENDPOINT, config.LLM_ENDPOINT)):
        try:
            extra = {"reasoning_effort": "low"} if "gpt-oss" in model else {}
            return client().chat.completions.create(model=model, messages=messages, max_tokens=500, temperature=0.7,
                                                    **({"tools": tool_list, "tool_choice": "auto"} if tool_list else {}), **extra)
        except Exception as e:  # noqa: BLE001
            last = e
            if "429" not in str(e) and "REQUEST_LIMIT" not in str(e):
                raise
            time.sleep(1.5 * (attempt + 1))
    raise last


def run_job(job: dict) -> dict | None:
    spec = AGENTS[job["agent"]]
    ctx = tools.Ctx(job["uid"])
    allowed = [t for t in tools.OPENAI_TOOLS if t["function"]["name"] in spec["tools"]]
    messages = [{"role": "system", "content": _system(spec)},
                {"role": "user", "content": "Context: " + tools.dumps(job["context"])}]
    node = f"agent.{job['agent']}"
    with span(spec["name"].replace(" ", "_").lower(), "AGENT") as root:
        root.set_inputs({"user_id": job["uid"], "acting_as": ctx.pid, "context": job["context"]})
        used = []
        for step in range(MAX_STEPS + 1):
            with span(f"llm_step_{step + 1}", "CHAT_MODEL") as s:
                resp = _complete(messages, allowed if step < MAX_STEPS else None)
                msg = resp.choices[0].message
                s.set_outputs({"content": msg.content if isinstance(msg.content, str) else str(msg.content)[:500],
                               "tool_calls": [c.function.name for c in (msg.tool_calls or [])]})
            if not msg.tool_calls:
                break
            messages.append({"role": "assistant", "content": None, "tool_calls": [
                {"id": c.id, "type": "function", "function": {"name": c.function.name, "arguments": c.function.arguments or "{}"}}
                for c in msg.tool_calls]})
            for c in msg.tool_calls:
                try:
                    args = json.loads(c.function.arguments or "{}")
                except json.JSONDecodeError:
                    args = {}
                with span(f"tool_{c.function.name}", "TOOL") as ts:
                    ts.set_inputs(args)
                    res, _ = tools.run(c.function.name, args, ctx)
                    ts.set_outputs(res)
                used.append(c.function.name)
                activity.hit(f"tool.{c.function.name}", detail=spec["name"], log=True)
                messages.append({"role": "tool", "tool_call_id": c.id, "content": tools.dumps(res)})
        content = msg.content if isinstance(msg.content, str) else "".join(
            p.get("text", "") for p in (msg.content or []) if isinstance(p, dict) and p.get("type") == "text")
        out = _parse(content or "")
        root.set_outputs({"card": out, "tools_used": used})
        trace_id = getattr(root, "trace_id", None)
    if job["agent"] == "evening_recap" and "get_gold_summary" not in used:
        log.warning("evening recap skipped get_gold_summary; keeping the template")
        return None
    if out:
        activity.hit(node, detail=out["title"] or spec["name"], trace_id=trace_id, log=True)
        return {**out, "trace_id": trace_id}
    return None


def _publish(job: dict, upgraded: dict) -> None:
    card = {**job["card"], "title": upgraded["title"] or job["card"]["title"], "body": upgraded["body"],
            "generated_by": "agent", "trace_id": upgraded["trace_id"]}
    u = store.get(job["uid"])
    u.add_card(card)
    broadcaster.publish(job["uid"], "card", card)
    landing.enqueue({"source": "app", "user_id": u.following or job["uid"], "kind": "card",
                     "t": iso_utc(utcnow()), "released_at": iso_utc(utcnow()),
                     "payload": {k: v for k, v in card.items() if k != "attachments"}})


def _worker() -> None:
    while True:
        job = _jobs.get()
        try:
            if not _budget_ok():
                counters["agent_fallbacks"] += 1
                continue
            upgraded = run_job(job)
            counters["agent_runs"] += 1
            if upgraded:
                _publish(job, upgraded)
            else:
                counters["agent_fallbacks"] += 1
        except Exception:  # noqa: BLE001 (the template card stays; nothing breaks for the phone)
            counters["agent_failures"] += 1
            log.exception("%s failed", job.get("agent"))


def start_workers(n: int = 2) -> None:
    for i in range(n):
        threading.Thread(target=_worker, daemon=True, name=f"agent-{i}").start()
