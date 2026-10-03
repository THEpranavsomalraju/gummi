"""IMU50 cadence-band check (D-19) on a laptop or any machine with internet: same code as notebook 04.

    python data\\scripts\\run_imu50_check.py --subjects 00 05 13 20 44 --hours 24

Each subject streams from the Zenodo zip in its own process (HTTP range requests, about 150 MB per subject-day,
never the 46.7 GB archive). Writes data/local_out/imu50/{minutes.csv, scoring.csv, hourly.csv, summary.json}.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import pandas as pd

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

from imu50 import hourly_check, subject_minutes  # noqa: E402


def _one(subject: str, hours: float):
    t = time.time()
    m, sc, mb = subject_minutes(subject, hours=hours)
    return subject, m, sc, mb, round(time.time() - t)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--subjects", nargs="+", default=["00", "05", "13", "20", "44"])
    ap.add_argument("--hours", type=float, default=24.0)
    ap.add_argument("--out", default=str(DATA / "local_out" / "imu50"))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    frames, scores, read_mb, secs, failed = [], [], {}, {}, {}
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=len(args.subjects)) as pool:
        futs = {pool.submit(_one, s.zfill(2), args.hours): s for s in args.subjects}
        for fut in as_completed(futs):
            s = futs[fut]
            try:
                s, m, sc, mb, sec = fut.result()
            except Exception as exc:
                failed[s] = f"{exc.__class__.__name__}: {str(exc)[:200]}"
                print(f"subject {s} FAILED: {failed[s]}", flush=True)
                continue
            frames.append(m); scores.append(sc); read_mb[s] = mb; secs[s] = sec
            print(f"subject {s}: {len(m)} minutes, {int(m['walking'].sum())} walking-like, {mb} MB, {sec}s", flush=True)
    if not frames:
        print("every subject failed", failed)
        return 1
    minutes = pd.concat(frames, ignore_index=True)
    scoring = pd.concat(scores, ignore_index=True)
    hourly, summary = hourly_check(minutes, scoring)
    summary.update({"hours_per_subject": args.hours, "mb_read": read_mb, "seconds_per_subject": secs,
                    "failed": failed, "seconds": round(time.time() - t0)})
    minutes.to_csv(out / "minutes.csv", index=False)
    scoring.to_csv(out / "scoring.csv", index=False)
    hourly.to_csv(out / "hourly.csv", index=False)
    (out / "summary.json").write_text(json.dumps(summary, indent=2, default=str))
    print(json.dumps(summary, indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
