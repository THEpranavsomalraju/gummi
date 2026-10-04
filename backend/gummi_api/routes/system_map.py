"""The Gummi system map: GET /map (canvas for the projector) and GET /map/state (live graph data, polled each second).

Every node is a real component; counts and "last active" come from gummi_api.activity, hit by the code that does the
work. Databricks nodes link to their workspace pages.
"""
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from .. import activity, config
from ..agent import events
from ..engine.engine import engine
from ..engine.gold import gold
from ..state.view import stream_status

router = APIRouter()
W = "https://dbc-0f92eb43-532a.cloud.databricks.com"
EXP = f"{W}/ml/experiments/{config.MLFLOW_EXPERIMENT_ID}"

# (id, label, sub, column, row, kind, activity keys, link)
NODES = [
    ("src_replay", "Study replay", "15 BIG IDEAs participants, 60x", 0, 0, "source", ["source.replay"], f"{W}/explore/data/workspace/gummi_data/replay_cgm"),
    ("src_phone", "iPhone", "steps and walks, live", 0, 2, "source", ["source.iphone"], None),
    ("src_dexcom", "Dexcom sandbox", "real OAuth, status only", 0, 4, "source", ["source.dexcom"], "https://developer.dexcom.com"),
    ("engine", "Replay engine", "Databricks App: hot state, 1 s tick", 1, 1, "app", ["engine.meal_due", "engine.walk_alert", "engine.morning_briefing", "engine.evening_recap"], f"{W}/apps/gummi"),
    ("model", "Gummi model", "ridge per horizon, 5 out-of-sample folds", 2, 0, "model", ["model.predict"], f"{W}/explore/data/models/workspace/gummi_ml/gummi_model"),
    ("grader", "Grader", "Gummi vs CGM-only vs last value", 2, 2, "model", ["model.grade"], None),
    ("llm", "gpt-oss-120b", "Databricks Foundation Model API", 2, 4, "databricks", [], f"{W}/ml/endpoints/{config.LLM_ENDPOINT}"),
    ("agent_coach", "Coach agent", "chat: talks, never invents numbers", 3, 0, "agent", ["agent.coach"], EXP),
    ("agent_meal", "Meal Story agent", "2 h after every meal", 3, 1, "agent", ["agent.meal_story"], EXP),
    ("agent_walk", "Walk Coach agent", "forecast crosses 140", 3, 2, "agent", ["agent.walk_coach"], EXP),
    ("agent_morning", "Morning Briefing agent", "first reading after 6 AM", 3, 3, "agent", ["agent.morning_briefing"], EXP),
    ("agent_recap", "Evening Recap agent", "8 PM, reads gold tables", 3, 4, "agent", ["agent.evening_recap"], EXP),
    ("agent_reviewer", "Reviewer agent", "scores every reply, writes lessons", 3, 5, "agent", ["agent.reviewer", "agent.self_check"], EXP),
    ("memory", "Lessons memory", "UC volume + prompt registry versions", 4, 6, "databricks", ["memory.lessons", "memory.prompt_registry"], f"{W}/explore/data/workspace/gummi_agent"),
    ("tool_simulate", "simulate_food", "can I eat this?", 4, 0, "tool", ["tool.simulate_food", "tool.log_meal"], None),
    ("tool_state", "get_state", "Gummi's estimate now", 4, 1, "tool", ["tool.get_state", "tool.today_summary", "tool.get_history"], None),
    ("tool_spike", "explain_spike", "why did I spike?", 4, 2, "tool", ["tool.explain_spike"], None),
    ("tool_walk", "suggest_walk", "modeled walk effect", 4, 3, "tool", ["tool.suggest_walk"], None),
    ("tool_gold", "get_gold_summary", "accuracy from gold", 4, 4, "tool", ["tool.get_gold_summary"], None),
    ("tool_ask", "ask_data", "deep look, own history", 4, 5, "tool", ["tool.ask_data"], None),
    ("landing", "Landing volume", "JSON lines every 5 s", 5, 0, "databricks", ["databricks.landing"], f"{W}/explore/data/volumes/workspace/gummi_data/landing"),
    ("pipeline", "Lakeflow pipeline", "gummi_stream: bronze, silver, gold", 5, 1, "databricks", ["databricks.pipeline"], f"{W}/pipelines/b11d910a-48c4-4396-922c-0c249303f33f"),
    ("gold", "Gold tables", "out-of-sample accuracy", 5, 2, "databricks", ["databricks.gold"], f"{W}/explore/data/workspace/gummi_data/stream_gold_accuracy"),
    ("insights", "Gummi Insights", "Agent Bricks supervisor", 5, 3, "agent", ["agent.insights"], f"{W}/ml/endpoints/{config.INSIGHTS_ENDPOINT}"),
    ("mlflow", "MLflow", "traces, judges, model registry", 5, 5, "databricks", [], EXP),
    ("ins_genie", "Genie: Gummi Data", "plain-English SQL", 6, 2, "databricks", ["insights.gummi-data"], f"{W}/genie/rooms/01f1bf87ea5918298b59e25b38538d16"),
    ("ins_fn", "UC functions", "get_gold_summary, meal_response_stats", 6, 3, "databricks", ["insights.workspace__gummi_data__get_gold_summary", "insights.workspace__gummi_data__meal_response_stats"], f"{W}/explore/data/workspace/gummi_data"),
    ("ins_ka", "Knowledge Assistant", "Gummi Reports (draft)", 6, 4, "databricks", ["insights.gummi-reports"], f"{W}/ml/endpoints/ka-d8755a47-endpoint"),
    ("dashboard", "AI/BI dashboard", "Gummi live accuracy", 6, 1, "databricks", [], f"{W}/dashboardsv3/01f1bf883268170693784c519c8eb10b/published"),
    ("out_phone", "Gummi on iPhone", "live channel, < 1 s", 6, 0, "output", [], None),
]
EDGES = [
    ("src_replay", "engine", "source.replay"), ("src_phone", "engine", "source.iphone"), ("src_dexcom", "engine", "source.dexcom"),
    ("engine", "model", "model.predict"), ("engine", "grader", "model.grade"), ("model", "grader", "model.grade"),
    ("engine", "agent_meal", "agent.meal_story"), ("engine", "agent_walk", "agent.walk_coach"),
    ("engine", "agent_morning", "agent.morning_briefing"), ("engine", "agent_recap", "agent.evening_recap"),
    ("llm", "agent_coach", "agent.coach"), ("llm", "agent_meal", "agent.meal_story"), ("llm", "agent_walk", "agent.walk_coach"),
    ("llm", "agent_morning", "agent.morning_briefing"), ("llm", "agent_recap", "agent.evening_recap"),
    ("agent_coach", "tool_simulate", "tool.simulate_food"), ("agent_coach", "tool_state", "tool.get_state"),
    ("agent_coach", "tool_spike", "tool.explain_spike"), ("agent_coach", "tool_walk", "tool.suggest_walk"),
    ("agent_coach", "tool_ask", "tool.ask_data"), ("agent_meal", "tool_spike", "tool.explain_spike"),
    ("agent_walk", "tool_walk", "tool.suggest_walk"), ("agent_morning", "tool_state", "tool.get_state"),
    ("agent_recap", "tool_gold", "tool.get_gold_summary"),
    ("tool_simulate", "model", None), ("tool_walk", "model", None),
    ("engine", "landing", "databricks.landing"), ("landing", "pipeline", "databricks.pipeline"),
    ("pipeline", "gold", "databricks.gold"), ("gold", "tool_gold", "tool.get_gold_summary"), ("gold", "dashboard", None),
    ("tool_ask", "insights", "agent.insights"), ("insights", "ins_genie", "insights.gummi-data"),
    ("insights", "ins_fn", "insights.workspace__gummi_data__get_gold_summary"), ("insights", "ins_ka", "insights.gummi-reports"),
    ("ins_genie", "gold", None), ("agent_coach", "mlflow", "agent.coach"), ("engine", "out_phone", None),
    ("agent_coach", "out_phone", "agent.coach"), ("agent_meal", "out_phone", "agent.meal_story"),
    ("agent_coach", "agent_reviewer", "agent.reviewer"), ("agent_reviewer", "memory", "memory.lessons"),
    ("memory", "agent_coach", "memory.lessons"), ("agent_reviewer", "mlflow", "agent.reviewer"),
]


@router.get("/map/state")
async def map_state():
    snap = activity.snapshot()
    st = stream_status()
    r = gold.rollup or {}
    nodes = []
    for nid, label, sub, col, row, kind, keys, link in NODES:
        hits = [snap["nodes"][k] for k in keys if k in snap["nodes"]]
        nodes.append({"id": nid, "label": label, "sub": sub, "col": col, "row": row, "kind": kind, "link": link,
                      "count": sum(h["count"] for h in hits), "ago_s": min((h["ago_s"] for h in hits), default=None),
                      "detail": next((h["detail"] for h in sorted(hits, key=lambda h: h["ago_s"]) if h["detail"]), None),
                      "trace_id": next((h["trace_id"] for h in hits if h.get("trace_id")), None)})
    edges = [{"from": a, "to": b, "ago_s": snap["nodes"].get(k, {}).get("ago_s") if k else None} for a, b, k in EDGES]
    return {"nodes": nodes, "edges": edges, "feed": snap["feed"],
            "stats": {"replay_clock": st["replay_clock"], "running": st["running"], "speed": st["speed"],
                      "events_per_second": st["events_per_second"], "pipeline_lag_seconds": st["pipeline_lag_seconds"],
                      "predictions": engine.counters["predictions"], "grades": engine.counters["grades"],
                      "agent_runs": events.counters["agent_runs"],
                      "gold": {"grades": r.get("grades"), "gummi": r.get("gummi_mae_mg_dl"),
                               "cgm_only": r.get("cgm_only_mae_mg_dl"), "last_value": r.get("last_value_mae_mg_dl")}},
            "experiment": EXP}


@router.get("/map", response_class=HTMLResponse)
async def map_page():
    return (Path(__file__).parents[1] / "web" / "map.html").read_text()


@router.get("/agent/lessons")
async def agent_lessons():
    from ..agent import reviewer
    return {"lessons": reviewer.lessons_detail(), "reviewer": reviewer.counters, "path": reviewer.LESSONS_PATH}
