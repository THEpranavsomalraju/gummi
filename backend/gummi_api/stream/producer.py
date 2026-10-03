"""Replay producer and replay clock (Phase 1: synthetic CGM for the replayed participants).

Replay time is minutes since day 1 00:00 participant-local. Replay day D maps to today's date in the profile timezone
(Data's D-33 replay clock proposal, accepted). CGM becomes visible delay_minutes after its event time, like Dexcom.
"""
import asyncio
import re
import time
from datetime import timedelta

from .. import config
from ..mock import data as mock
from ..util import iso, iso_utc, local_midnight, utcnow
from .landing_writer import landing

START_RE = re.compile(r"^day(\d+)T(\d{2}):(\d{2})$")


def parse_start(start_at: str | None) -> float:
    m = START_RE.match(start_at or "day1T06:00")
    if not m:
        raise ValueError("start_at must look like day3T06:00")
    day, hh, mm = map(int, m.groups())
    return (day - 1) * 1440 + hh * 60 + mm


def clock_label(replay_min: float) -> str:
    day, rem = divmod(int(replay_min), 1440)
    return f"day{day + 1}T{rem // 60:02d}:{rem % 60:02d}"


class ReplayClock:
    def __init__(self):
        self.running = False
        self.paused = False
        self.speed = 60.0
        self.delay_minutes = config.DELAY_MINUTES
        self.start_day = 1
        self.anchor_replay: float | None = None      # replay minutes at anchor_wall
        self.anchor_wall: float | None = None        # unix seconds
        self.events_released = 0
        self._rate: list[tuple[float, int]] = []
        self._last_emitted: float | None = None

    def now(self) -> float | None:
        if self.anchor_replay is None:
            return None
        if not self.running or self.paused:
            return self.anchor_replay
        return self.anchor_replay + (time.time() - self.anchor_wall) * self.speed / 60.0

    def _reanchor(self) -> None:
        self.anchor_replay, self.anchor_wall = self.now(), time.time()

    def replay_to_wall(self, replay_min: float):
        """Replay minutes -> datetime on today's date (D-33)."""
        return local_midnight(utcnow()) + timedelta(minutes=replay_min - (self.start_day - 1) * 1440)

    def start(self, speed: float, delay_minutes: int, start_at: str | None) -> None:
        self.anchor_replay = parse_start(start_at)
        self.start_day = int(self.anchor_replay // 1440) + 1
        self.anchor_wall = time.time()
        self.speed, self.delay_minutes = float(speed), int(delay_minutes)
        self.running, self.paused = True, False
        self._last_emitted = self.anchor_replay - self.delay_minutes

    def stop(self) -> None:
        self._reanchor()
        self.running, self.paused = False, False

    def pause(self) -> None:
        if self.running and not self.paused:
            self._reanchor()
            self.paused = True

    def resume(self) -> None:
        if self.running and self.paused:
            self.anchor_wall = time.time()
            self.paused = False

    def set_speed(self, speed: float) -> None:
        self._reanchor()
        self.speed = float(speed)

    def status(self, pipeline_lag_seconds: float | None = None) -> dict:
        now = self.now()
        cutoff = time.time() - 30
        self._rate = [(t, n) for t, n in self._rate if t >= cutoff]
        eps = sum(n for _, n in self._rate) / 30.0 if self.running and not self.paused else 0.0
        return {"running": self.running, "paused": self.paused, "speed": self.speed,
                "delay_minutes": self.delay_minutes, "participants": len(config.PARTICIPANTS),
                "replay_clock": clock_label(now) if now is not None else None,
                "replay_anchor": {"replay_time": iso(self.replay_to_wall(self.anchor_replay)) if now is not None else None,
                                  "wall_time": iso(utcnow().fromtimestamp(self.anchor_wall, utcnow().tzinfo))
                                  if self.anchor_wall else None},
                "events_released": self.events_released, "events_per_second": round(eps, 2),
                "pipeline_lag_seconds": pipeline_lag_seconds}

    def tick(self) -> int:
        """Release every CGM reading whose visibility time (event time + delay) passed since the last tick."""
        now = self.now()
        if not self.running or self.paused or now is None:
            return 0
        visible_until = now - self.delay_minutes
        released_at = iso_utc(utcnow())
        n = 0
        t = (int(self._last_emitted // 5) + 1) * 5
        while t <= visible_until:
            when = self.replay_to_wall(t)
            for pid in config.PARTICIPANTS:
                landing.enqueue({"source": "replay", "user_id": pid, "kind": "cgm", "t": iso_utc(when),
                                 "released_at": released_at, "payload": {"glucose_mg_dl": mock.glucose_at(pid, when)}})
                n += 1
            self._last_emitted = t
            t += 5
        self.events_released += n
        self._rate.append((time.time(), n))
        return n

    async def run(self) -> None:
        while True:
            await asyncio.sleep(5)
            self.tick()


clock = ReplayClock()
