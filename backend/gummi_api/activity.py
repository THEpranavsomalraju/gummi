"""Live activity for the system map (/api/v1/map): what each part of Gummi did, counted and timestamped.

Every component calls hit(node, ...) when it does real work (an event released, a prediction made, a tool called,
an agent run traced). The map page polls a snapshot once a second. Thread-safe and allocation-light.
"""
import threading
import time
from collections import deque

_lock = threading.Lock()
_counts: dict[str, int] = {}
_last: dict[str, float] = {}
_detail: dict[str, str] = {}
_feed: deque = deque(maxlen=40)
_traces: dict[str, str] = {}           # agent node -> last MLflow trace id


def hit(node: str, n: int = 1, detail: str | None = None, trace_id: str | None = None, log: bool = False) -> None:
    now = time.time()
    with _lock:
        _counts[node] = _counts.get(node, 0) + n
        _last[node] = now
        if detail:
            _detail[node] = detail
        if trace_id:
            _traces[node] = trace_id
        if log:
            _feed.appendleft({"t": now, "node": node, "detail": detail or node})


_last_viewer = time.time()


def viewer_seen() -> None:
    """Something is watching (a /live phone, the map, or the fleet view): keep the replay and gold refresh going."""
    global _last_viewer
    _last_viewer = time.time()


def idle_seconds() -> float:
    return time.time() - _last_viewer


def snapshot() -> dict:
    now = time.time()
    with _lock:
        return {"now": now,
                "nodes": {k: {"count": _counts[k], "ago_s": round(now - _last[k], 1), "detail": _detail.get(k),
                              "trace_id": _traces.get(k)} for k in _counts},
                "feed": [{**f, "ago_s": round(now - f["t"], 1)} for f in list(_feed)[:14]]}
