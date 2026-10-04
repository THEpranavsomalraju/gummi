"""LLM access: the D-04 chat endpoint (OpenAI-compatible, Databricks serving) and the Gummi Insights supervisor."""
import logging
import threading
import warnings

from .. import config

log = logging.getLogger("gummi.llm")
_client = None
_lock = threading.Lock()


def client():
    """One OpenAI-compatible client against <workspace>/serving-endpoints; the SDK refreshes the App's OAuth token."""
    global _client
    with _lock:
        if _client is None:
            from databricks.sdk import WorkspaceClient
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                _client = WorkspaceClient().serving_endpoints.get_open_ai_client()
        return _client


_pool = None


def ask_insights(question: str, timeout_s: float = 25.0) -> str | None:
    """Gummi Insights (Agent Bricks supervisor, D-52). Slow by nature, so a hard timeout; None means fall back."""
    global _pool
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutTimeout
    with _lock:
        _pool = _pool or ThreadPoolExecutor(max_workers=2, thread_name_prefix="insights")
    fut = _pool.submit(_ask_insights, question)
    try:
        return fut.result(timeout=timeout_s)
    except FutTimeout:
        log.warning("Gummi Insights timed out after %.0f s", timeout_s)
        return None


def _ask_insights(question: str) -> str | None:
    try:
        from databricks.sdk import WorkspaceClient
        w = WorkspaceClient()
        resp = w.api_client.do("POST", f"/serving-endpoints/{config.INSIGHTS_ENDPOINT}/invocations",
                               body={"input": [{"role": "user", "content": question}]},
                               headers={"Content-Type": "application/json"})
        texts = [c.get("text", "") for item in resp.get("output", []) if item.get("type") == "message"
                 for c in item.get("content", []) if c.get("type") == "output_text"]
        from .. import activity
        for item in resp.get("output", []):
            if item.get("type") == "function_call":       # which sub-agent the supervisor chose, for the map
                activity.hit(f"insights.{item.get('name', 'tool')}", detail=question[:60], log=True)
        activity.hit("agent.insights", detail=question[:60], log=True)
        return texts[-1].strip() if texts else None
    except Exception as e:  # noqa: BLE001
        log.warning("Gummi Insights failed: %s", str(e)[:200])
        return None


def warm() -> None:
    """At startup: one tiny call per chat model and one throwaway MLflow span, so the first real chat turn pays for
    neither connection setup nor tracing setup (the first span costs about 2 s, later ones about 0)."""
    for model in (config.LLM_ENDPOINT, *config.LLM_FALLBACKS):
        try:
            client().with_options(max_retries=0).chat.completions.create(
                model=model, max_tokens=1, messages=[{"role": "user", "content": "hi"}],
                **({"reasoning_effort": "low"} if "gpt-oss" in model else {}))
        except Exception as e:  # noqa: BLE001
            log.warning("LLM warmup failed for %s: %s", model, str(e)[:120])
    try:
        from .chat import span
        with span("warmup", "UNKNOWN") as s:
            s.set_inputs({"warmup": True})
    except Exception:  # noqa: BLE001
        pass


__all__ = ["client", "ask_insights", "warm"]
