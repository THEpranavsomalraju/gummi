"""Replay clock (CONTRACT section 3 StreamStatus, D-45).

Replay time is minutes since day 1 00:00 participant-local (the t_offset_min of Data's replay tables). Replay day D
maps to the demo date in the profile timezone: local clock time on the start day becomes the same clock time today
(D-45). The demo date is frozen at /stream/start so a replay that crosses midnight keeps one timeline.
"""
import re
import time
from datetime import datetime, timedelta, timezone

from .. import config
from ..util import iso, local_midnight, utcnow

START_RE = re.compile(r"^day(\d+)T(\d{2}):(\d{2})$")


def parse_start(start_at: str | None) -> float:
    m = START_RE.match(start_at or config.DEFAULT_START)
    if not m:
        raise ValueError("start_at must look like day6T05:00")
    day, hh, mm = map(int, m.groups())
    if day < 1 or hh > 23 or mm > 59:
        raise ValueError("start_at must look like day6T05:00")
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
        self.demo_midnight = local_midnight(utcnow())
        self.anchor_replay: float | None = None      # replay minutes at anchor_wall
        self.anchor_wall: float | None = None        # unix seconds
        self.events_released = 0
        self._rate: list[tuple[float, int]] = []

    def now(self) -> float | None:
        if self.anchor_replay is None:
            return None
        if not self.running or self.paused:
            return self.anchor_replay
        return self.anchor_replay + (time.time() - self.anchor_wall) * self.speed / 60.0

    def _reanchor(self) -> None:
        self.anchor_replay, self.anchor_wall = self.now(), time.time()

    def replay_to_wall(self, replay_min: float) -> datetime:
        """Replay minutes -> the mapped timestamp on the demo date (D-45). Used for every event time."""
        return self.demo_midnight + timedelta(minutes=replay_min - (self.start_day - 1) * 1440)

    def replay_to_real(self, replay_min: float) -> datetime | None:
        """When the replay clock will reach replay_min, in real wall-clock time (for phone notifications, D-36)."""
        if not self.running or self.paused or self.anchor_replay is None:
            return None
        return datetime.fromtimestamp(self.anchor_wall + (replay_min - self.anchor_replay) * 60.0 / self.speed, timezone.utc)

    def start(self, speed: float, delay_minutes: int, start_at: str | None) -> None:
        self.anchor_replay = parse_start(start_at)
        self.start_day = int(self.anchor_replay // 1440) + 1
        self.demo_midnight = local_midnight(utcnow())
        self.anchor_wall = time.time()
        self.speed, self.delay_minutes = float(speed), int(delay_minutes)
        self.running, self.paused = True, False
        self.events_released, self._rate = 0, []

    def stop(self) -> None:
        if self.anchor_replay is not None:
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
        if self.anchor_replay is not None:
            self._reanchor()
        self.speed = float(speed)

    def count(self, n: int) -> None:
        self.events_released += n
        self._rate.append((time.time(), n))

    def status(self, pipeline_lag_seconds: float | None = None) -> dict:
        now = self.now()
        cutoff = time.time() - 30
        self._rate = [(t, n) for t, n in self._rate if t >= cutoff]
        eps = sum(n for _, n in self._rate) / 30.0 if self.running and not self.paused else 0.0
        anchored = now is not None
        return {"running": self.running, "paused": self.paused, "speed": self.speed,
                "delay_minutes": self.delay_minutes, "participants": len(config.PARTICIPANTS),
                "replay_clock": clock_label(now) if anchored else None,
                "replay_anchor": {"replay_time": iso(self.replay_to_wall(self.anchor_replay)) if anchored else None,
                                  "wall_time": iso(datetime.fromtimestamp(self.anchor_wall, timezone.utc)) if anchored else None},
                "events_released": self.events_released, "events_per_second": round(eps, 2),
                "pipeline_lag_seconds": pipeline_lag_seconds}


clock = ReplayClock()
