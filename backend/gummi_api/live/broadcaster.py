"""Per-user server-sent events fan-out (CONTRACT section 5). Publishing never blocks: a slow phone drops old events."""
import asyncio
import json
from collections import defaultdict

from .. import config
from ..util import iso, utcnow


def sse(event: str, data) -> str:
    return f"event: {event}\ndata: {json.dumps(data, separators=(',', ':'))}\n\n"


class Broadcaster:
    def __init__(self):
        self._subs: dict[str, set[asyncio.Queue]] = defaultdict(set)

    def users(self) -> list[str]:
        return [u for u, qs in self._subs.items() if qs]

    def connections(self) -> int:
        return sum(len(qs) for qs in self._subs.values())

    def publish(self, user_id: str, event: str, data) -> None:
        msg = sse(event, data)
        for q in list(self._subs.get(user_id, ())):
            if q.full():
                try:
                    q.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            q.put_nowait(msg)

    def publish_all(self, event: str, data) -> None:
        for user_id in self.users():
            self.publish(user_id, event, data)

    async def stream(self, user_id: str, first: list[str], ping_seconds: float = config.PING_SECONDS):
        q: asyncio.Queue = asyncio.Queue(maxsize=100)
        self._subs[user_id].add(q)
        try:
            yield ": connected\n\n"
            for msg in first:
                yield msg
            while True:
                try:
                    yield await asyncio.wait_for(q.get(), timeout=ping_seconds)
                except asyncio.TimeoutError:
                    yield sse("ping", {"t": iso(utcnow())})
        finally:
            self._subs[user_id].discard(q)


broadcaster = Broadcaster()
