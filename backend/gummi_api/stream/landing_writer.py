"""Landing writer: drains StreamEvents every 5 seconds into one JSON lines file per batch and source.

Rules the gummi_stream pipeline relies on (Data handoff item 7): one complete file per batch written in a single
upload call (never appended), file name <YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl in UTC, unique event_id, ISO UTC times.
Runs off the request path; uploads go through a thread so the event loop never waits on the Files API.
"""
import asyncio
import io
import json
import logging
import threading
from collections import defaultdict

from .. import config
from ..util import new_id, utcnow

log = logging.getLogger("gummi.landing")


class LandingWriter:
    def __init__(self, directory: str = config.LANDING_DIR, enabled: bool = config.LANDING_ENABLED):
        self.directory = directory
        self.enabled = enabled
        self.queue: list[dict] = []
        self.seq = 0
        self.files_written = 0
        self.events_written = 0
        self.last_file: str | None = None
        self.last_error: str | None = None
        self._client = None
        self._lock = threading.Lock()          # the engine tick enqueues from a worker thread

    def enqueue(self, event: dict) -> None:
        if self.enabled:
            event.setdefault("event_id", new_id("ev") + f"_{utcnow():%H%M%S%f}")
            with self._lock:
                self.queue.append(event)
                if len(self.queue) > 50_000:            # landing outage: keep memory bounded, drop oldest
                    del self.queue[:10_000]

    def _workspace(self):
        if self._client is None:
            from databricks.sdk import WorkspaceClient
            self._client = WorkspaceClient()        # App service principal in Databricks, DATABRICKS_CONFIG_PROFILE locally
        return self._client

    def _upload(self, path: str, body: bytes) -> None:
        self._workspace().files.upload(path, io.BytesIO(body), overwrite=False)

    async def flush(self) -> None:
        if not self.queue:
            return
        with self._lock:
            batch, self.queue = self.queue, []
        by_source: dict[str, list[dict]] = defaultdict(list)
        for ev in batch:
            by_source[ev["source"]].append(ev)
        stamp = f"{utcnow():%Y%m%dT%H%M%S}"
        for source, events in by_source.items():
            self.seq += 1
            path = f"{self.directory}/{stamp}_{source}_{self.seq:04d}.jsonl"
            body = "".join(json.dumps(e, separators=(",", ":")) + "\n" for e in events).encode()
            for attempt in range(3):
                try:
                    await asyncio.to_thread(self._upload, path, body)
                    self.files_written += 1
                    self.events_written += len(events)
                    self.last_file, self.last_error = path, None
                    break
                except Exception as e:  # noqa: BLE001 (any SDK or network error: retry, then requeue)
                    self.last_error = f"{type(e).__name__}: {str(e)[:200]}"
                    await asyncio.sleep(0.5 * 2 ** attempt)
            else:
                log.warning("landing upload failed, requeued %d events: %s", len(events), self.last_error)
                with self._lock:
                    self.queue[:0] = events

    async def run(self) -> None:
        while True:
            await asyncio.sleep(config.LANDING_INTERVAL_S)
            try:
                await self.flush()
            except Exception as e:  # noqa: BLE001
                self.last_error = f"{type(e).__name__}: {str(e)[:200]}"

    def status(self) -> dict:
        return {"enabled": self.enabled, "directory": self.directory, "queued": len(self.queue),
                "files_written": self.files_written, "events_written": self.events_written,
                "last_file": self.last_file, "last_error": self.last_error}


landing = LandingWriter()
