"""Read IMU50 subjects out of the Zenodo zip with HTTP range requests (no full download)."""
from __future__ import annotations

import io
import time
import urllib.request
import zipfile

import numpy as np
import pandas as pd

from .cadence import FS, minute_features

IMU50_URL = "https://zenodo.org/api/records/21468410/files/IMU50.zip/content"
IMU50_SIZE = 46_705_238_271


class HttpRangeFile(io.RawIOBase):
    """Read-only, seekable file over HTTP range requests, with a small block cache (enough for zipfile)."""

    def __init__(self, url: str, size: int, block: int = 8 << 20, max_blocks: int = 8):
        self.url, self.size, self.pos, self.block, self.max_blocks = url, size, 0, block, max_blocks
        self.cache: dict[int, bytes] = {}
        self.bytes_read = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def _block(self, i: int) -> bytes:
        if i not in self.cache:
            start = i * self.block
            end = min(start + self.block, self.size) - 1
            self.cache[i] = self._fetch(start, end)
            self.bytes_read += len(self.cache[i])
            while len(self.cache) > self.max_blocks:
                self.cache.pop(next(iter(self.cache)))
        return self.cache[i]

    def _fetch(self, start: int, end: int, attempts: int = 6) -> bytes:
        """One range request, retried with backoff: long Zenodo streams get dropped now and then."""
        want = end - start + 1
        for k in range(attempts):
            try:
                req = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}",
                                                                 "User-Agent": "gummi-imu50-check/1.0"})
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                if len(data) == want:
                    return data
                raise IOError(f"short read {len(data)} of {want} bytes")
            except Exception:
                if k == attempts - 1:
                    raise
                time.sleep(min(30, 2 ** k))
        raise AssertionError("unreachable")

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        n = max(0, min(n, self.size - self.pos))
        out = bytearray()
        while n > 0:
            i = self.pos // self.block
            blk = self._block(i)
            off = self.pos - i * self.block
            take = min(n, len(blk) - off)
            out += blk[off:off + take]
            self.pos += take
            n -= take
        return bytes(out)

    def readinto(self, b):
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


def open_subject(subject: str, url: str = IMU50_URL, size: int = IMU50_SIZE):
    """(outer HttpRangeFile, inner ZipFile) for one subject, e.g. "05"."""
    f = HttpRangeFile(url, size)
    outer = zipfile.ZipFile(f)
    inner = zipfile.ZipFile(outer.open(f"IMU50/DATA/{subject}.zip"))
    return f, inner


def subject_minutes(subject: str, hours: float = 24.0, url: str = IMU50_URL, size: int = IMU50_SIZE):
    """Per-minute cadence features for the first `hours` of a subject, plus the subject's hourly scoring.

    Streams the subject's IMU CSV from the start and stops after `hours`; returns (minutes, scoring, MB read).
    """
    f, inner = open_subject(subject, url, size)
    scoring = pd.read_csv(inner.open(f"{subject}/{subject}_scoring.csv"), parse_dates=["Timestamp"])
    scoring.insert(0, "subject", subject)
    rows, carry, start = [], None, None
    need = int(hours * 3600 * FS)
    seen = 0
    with inner.open(f"{subject}/{subject}_imu.csv") as fh:
        for chunk in pd.read_csv(fh, chunksize=FS * 60 * 30,
                                 usecols=["Timestamp", "Accelerometer X", "Accelerometer Y", "Accelerometer Z"]):
            if carry is not None:
                chunk = pd.concat([carry, chunk], ignore_index=True)
            chunk["minute"] = pd.to_datetime(chunk["Timestamp"]).dt.floor("min")
            last = chunk["minute"].iloc[-1]
            done, carry = chunk[chunk["minute"] < last], chunk[chunk["minute"] == last].drop(columns="minute")
            for minute, g in done.groupby("minute"):
                feats = minute_features(g[["Accelerometer X", "Accelerometer Y", "Accelerometer Z"]].to_numpy())
                rows.append({"subject": subject, "minute": minute, **feats})
            seen += len(done)
            if start is None and len(done):
                start = done["minute"].iloc[0]
            if seen >= need:
                break
    return pd.DataFrame(rows), scoring, round(f.bytes_read / 1e6, 1)
