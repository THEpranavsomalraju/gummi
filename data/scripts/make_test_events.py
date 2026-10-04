"""Write sample StreamEvent JSON-lines files (CONTRACT.md section 3) from real replay data and real model calls.

Used by the streaming spike (notebooks/03_streaming_spike.py), as test input for the gummi_stream pipeline, and as a
reference for the Backend's landing writer. CGM readings, meals, predictions, grades and cards come from the
BIG IDEAs replay tables and gummi_model calls. Only the u_demo walk, step and chat lines are made up.

    py data\\scripts\\make_test_events.py

Inputs (from run_local_pipeline.py): data/local_out/{replay_cgm.csv, replay_meals.csv, gummi_model_v1/}.
Outputs in data/pipelines/gummi_stream/sample_events/:
  <YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl   one file per source per 5-second batch
  EXPECTED.json                            row counts and gold numbers the pipeline should reproduce

v1.1: each replay participant is predicted and graded by model.for_user(user_id), the fold model that never saw
them (D-26). Predictions carry cgm_only_peak_mg_dl and last_value_peak_mg_dl; the CGM-only curve stays local (like
the App's hot state) for grading. The u_demo phone walk overlays the first (followed) participant, so the grade
windows it overlaps get walk_effect_graded false and drop out of gold accuracy (D-28). Excluded participants
(D-20, 015) are not replayed (D-37).

Replay clock used here (a proposal for the Backend's producer, not a contract): a participant's local clock time
on replay day D maps to the same wall-clock time on --date in --tz, stored as UTC, and the participant's profile
carries that timezone so gummi_model's time-of-day features stay local. CGM readings are released 60 minutes after
their reading time. The landing writer flushes every 5 seconds, so at --speed 60 one batch covers 5 replay
minutes. File stamps are wall-clock flush times starting at --wall-start.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

from gummi_activity import summarize_walk  # noqa: E402
from gummi_model import GlucoseModel, UserContext  # noqa: E402

DELAY = pd.Timedelta(minutes=60)
MACROS = ["carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g"]
MEAL_WINDOW = pd.Timedelta(minutes=120)


def iso(ts) -> str:
    return pd.Timestamp(ts).tz_convert("UTC").isoformat()


def _json_default(o):
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return float(o)
    if isinstance(o, (np.bool_,)):
        return bool(o)
    if isinstance(o, pd.Timestamp):
        return iso(o)
    raise TypeError(f"not JSON serializable: {type(o)}")


def to_clock(t_offset_min: pd.Series, replay_day: int, date: str, tz: str) -> pd.Series:
    """Participant-local minutes since their first midnight -> UTC on the replay clock."""
    local = pd.Timestamp(date) + pd.to_timedelta(t_offset_min - (replay_day - 1) * 1440, unit="min")
    utc = pd.Series(local).dt.tz_localize(tz, ambiguous="NaT", nonexistent="shift_forward").dt.tz_convert("UTC")
    return utc.dt.round("s")


def pick_day(rc: pd.DataFrame, rm: pd.DataFrame, pid: str) -> tuple[int, float]:
    """First standardized-breakfast day with CGM coverage from 2 h before to 4 h after and a later meal."""
    c = rc[rc.participant_id == pid]
    m = rm[rm.participant_id == pid]
    for _, b in m[m.is_standard_breakfast].sort_values("t_offset_min").iterrows():
        lo, hi = b.t_offset_min - 120, b.t_offset_min + 240
        n = int(c.t_offset_min.between(lo, hi).sum())
        later = m[(m.day_index == b.day_index) & (m.t_offset_min > b.t_offset_min + 120)]
        if n >= 0.95 * (hi - lo) / 5 and len(later):
            return int(b.day_index), float(b.t_offset_min)
    raise SystemExit(f"no standardized breakfast day with full CGM coverage for participant {pid}")


def describe(row) -> str:
    if bool(row["is_standard_breakfast"]):
        return "the standard breakfast"
    names = [n.strip().lower() for n in str(row["items"]).split(" | ") if n.strip()]
    if not names:
        return "that meal"
    return names[0] if len(names) == 1 else (", ".join(names[:2]) + (" and more" if len(names) > 2 else ""))


def _pct(flags: pd.Series):
    f = flags.dropna()
    return round(100.0 * float(f.astype(float).mean()), 1) if len(f) else None


def _avg(x: pd.Series):
    x = x.dropna()
    return round(float(x.mean()), 1) if len(x) else None


def gold_accuracy(grades: pd.DataFrame, preds: pd.DataFrame, meals: pd.DataFrame) -> list[dict]:
    """Same rules as pipelines/gummi_stream/03_gold.sql stream_gold_accuracy (v1.1)."""
    g = grades[grades["walk_effect_graded"].fillna(True).astype(bool)].copy()
    g = g.merge(preds[["prediction_id", "window_start", "window_end"]], on="prediction_id", how="left")
    near = []
    for _, r in g.iterrows():
        mm = meals[(meals.user_id == r.user_id) & (meals.eaten_at >= r.window_start - pd.Timedelta(minutes=180))
                   & (meals.eaten_at <= r.window_end)]
        near.append(len(mm))
    g["window_type"] = np.where((g["kind"] == "meal") | (np.array(near) > 0), "meal", "quiet")
    g["sample"] = np.where(g["user_id"].str.startswith("p_"), "out-of-sample", "live")
    rows = []
    for keys in (["sample", "user_id", "window_type"], ["sample", "user_id"], ["sample", "window_type"], ["sample"]):
        for k, grp in g.groupby(keys):
            k = k if isinstance(k, tuple) else (k,)
            d = dict(zip(keys, k))
            rows.append({
                "sample": d["sample"], "user_id": d.get("user_id", "ALL"), "window_type": d.get("window_type", "all"),
                "grades": int(len(grp)),
                "gummi_mae_mg_dl": _avg(grp.gummi_mae_mg_dl),
                "cgm_only_mae_mg_dl": _avg(grp.cgm_only_mae_mg_dl),
                "last_value_mae_mg_dl": _avg(grp.last_value_mae_mg_dl),
                "gummi_beats_cgm_only_pct": _pct(grp.gummi_beats_cgm_only),
                "gummi_beats_last_value_pct": _pct(grp.gummi_beats_last_value),
            })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--local-out", default=str(DATA / "local_out"))
    ap.add_argument("--out", default=str(DATA / "pipelines" / "gummi_stream" / "sample_events"))
    ap.add_argument("--date", default="2026-10-04", help="replay clock date")
    ap.add_argument("--tz", default="America/New_York", help="replay clock timezone (profile timezone)")
    ap.add_argument("--participants", nargs="*", default=["012", "004", "009"],
                    help="first one is the followed participant (D-15: 012)")
    ap.add_argument("--replay-day", type=int, default=6, help="D-15: day 6; 0 picks the first participant's first clean standardized-breakfast day")
    ap.add_argument("--hours", type=float, default=6.0, help="replay hours of released events")
    ap.add_argument("--speed", type=float, default=60.0)
    ap.add_argument("--wall-start", default="2026-10-04T13:00:00Z")
    ap.add_argument("--nowcast-every-min", type=int, default=60)
    args = ap.parse_args()

    lo = Path(args.local_out)
    rc = pd.read_csv(lo / "replay_cgm.csv", dtype={"participant_id": str})
    rm = pd.read_csv(lo / "replay_meals.csv", dtype={"participant_id": str})
    from gummi_model import config as C
    model = GlucoseModel.load(lo / C.VERSION)
    first = args.participants[0]
    for pid in args.participants:
        if pid not in set(rc.participant_id):
            raise SystemExit(f"participant {pid} is not in the replay tables (excluded under D-20, or unknown)")
    if not args.replay_day:
        replay_day, bf_off = pick_day(rc, rm, first)
    else:
        replay_day = args.replay_day
        bf = rm[(rm.participant_id == first) & (rm.day_index == replay_day) & rm.is_standard_breakfast]
        bf_off = float(bf.t_offset_min.iloc[0]) if len(bf) else (replay_day - 1) * 1440 + 7 * 60
    w0 = to_clock(pd.Series([bf_off - 60.0]), replay_day, args.date, args.tz).iloc[0]
    w1 = w0 + pd.Timedelta(hours=args.hours)
    profile = {"timezone": args.tz, "high_line_mg_dl": 140.0, "low_line_mg_dl": 70.0}

    events: list[dict] = []
    preds_rows, grade_rows, meal_rows = [], [], []

    def ev(source, user, kind, t, released, payload):
        events.append({"event_id": f"ev_{len(events) + 1:06d}", "source": source, "user_id": user, "kind": kind,
                       "t": iso(t), "released_at": iso(released), "payload": payload})

    def ctx_at(user, c, m, now):
        cgm = c[c.t <= now - DELAY][["t", "glucose_mg_dl"]]
        meals = m[m.eaten_at <= now][["eaten_at"] + MACROS]
        return UserContext(user, profile, cgm, meals, None, None), cgm

    # the teammate's phone walk (u_demo) 20 minutes after the followed participant's breakfast; it overlays p_<first>
    walk_start = to_clock(pd.Series([bf_off + 20.0]), replay_day, args.date, args.tz).iloc[0]
    overlay = [{"started_at": iso(walk_start), "minutes": 10}]

    def add_grade(pm, user, pred, c, graded_at):
        if graded_at >= w1:
            return None
        g = pm.grade(pred, c[c.t <= graded_at - DELAY][["t", "glucose_mg_dl"]],
                     overlay_walks=overlay if user == f"p_{first}" else None)
        if g.get("status") != "graded":
            return None
        g["grade_id"] = "g_" + pred["prediction_id"][3:]
        g["graded_at"] = iso(graded_at)
        ev("app", user, "grade", graded_at, graded_at, g)
        grade_rows.append({"user_id": user, **g})
        return g

    def peak(curve):
        return max(p["glucose_mg_dl"] for p in curve) if curve else None

    folds = {}
    for pid in args.participants:
        user = f"p_{pid}"
        pm = model.for_user(user)
        folds[user] = pm.version
        c = rc[rc.participant_id == pid].copy()
        c["t"] = to_clock(c.t_offset_min, replay_day, args.date, args.tz).to_numpy()
        m = rm[rm.participant_id == pid].copy()
        m["eaten_at"] = to_clock(m.t_offset_min, replay_day, args.date, args.tz).to_numpy()

        for _, r in c[(c.t + DELAY >= w0) & (c.t + DELAY < w1)].iterrows():
            ev("replay", user, "cgm", r.t, r.t + DELAY, {"glucose_mg_dl": round(float(r.glucose_mg_dl), 1)})

        for _, r in m[(m.eaten_at >= w0) & (m.eaten_at < w1)].iterrows():
            eat = r.eaten_at
            mid = r.meal_id
            totals = {k: (None if pd.isna(r[k]) else round(float(r[k]), 1)) for k in MACROS + ["calories"]}
            items = [{"name": n.strip(), "nutrition_source": "dataset", "editable": False}
                     for n in str(r["items"]).split(" | ") if n.strip()]
            ev("replay", user, "meal", eat, eat, {"meal_id": f"m_{mid}", "eaten_at": iso(eat), "source": "replay",
                                                 "items": items, "totals": totals, "prediction_id": f"pr_{mid}"})
            meal_rows.append({"user_id": user, "eaten_at": eat})
            ctx, cgm = ctx_at(user, c, m, eat)
            minutes = int(MEAL_WINDOW.total_seconds() // 60)
            curve = pm.forecast(ctx, eat, minutes)
            cgm_curve = pm.cgm_only_forecast(ctx, eat, minutes)
            about = describe(r)
            pred = {"prediction_id": f"pr_{mid}", "kind": "meal", "made_at": iso(eat), "about": about,
                    "meal_id": f"m_{mid}", "window_start": iso(eat), "window_end": iso(eat + MEAL_WINDOW),
                    "predicted_peak_mg_dl": peak(curve), "predicted_curve": curve,
                    "cgm_only_peak_mg_dl": peak(cgm_curve),
                    "last_value_peak_mg_dl": round(float(cgm.glucose_mg_dl.iloc[-1]), 1), "status": "pending"}
            ev("app", user, "prediction", eat, eat, pred)
            preds_rows.append({"prediction_id": pred["prediction_id"], "window_start": eat, "window_end": eat + MEAL_WINDOW})
            graded_at = eat + MEAL_WINDOW + DELAY
            g = add_grade(pm, user, {**pred, "cgm_only_curve": cgm_curve}, c, graded_at)
            if g is not None:
                ev("app", user, "card", graded_at, graded_at, {
                    "card_id": f"c_{mid}", "type": "meal_story", "created_at": iso(graded_at),
                    "title": f"{about[0].upper() + about[1:]}, two hours later", "body": g["message"],
                    "mood": "proud" if g.get("gummi_beats_cgm_only") else "calm",
                    "actions": [{"label": "Ask Gummi why", "kind": "open_chat",
                                 "prompt": f"Why did I peak at {g['actual_peak_mg_dl']:.0f}?"}],
                    "trace_id": None, "generated_by": "template"})

        now = w0 + pd.Timedelta(minutes=30)
        k = 0
        while now + DELAY < w1:
            ctx, cgm = ctx_at(user, c, m, now)
            curve = pm.estimate_gap(ctx, now)
            if curve:
                k += 1
                cgm_curve = pm.cgm_only_forecast(ctx, now, minutes=0, include_gap=True)
                pred = {"prediction_id": f"pr_{pid}-now{k:02d}", "kind": "nowcast", "made_at": iso(now),
                        "about": "the last hour", "meal_id": None,
                        "window_start": curve[0]["t"], "window_end": curve[-1]["t"],
                        "predicted_peak_mg_dl": peak(curve), "predicted_curve": curve,
                        "cgm_only_peak_mg_dl": peak(cgm_curve),
                        "last_value_peak_mg_dl": round(float(cgm.glucose_mg_dl.iloc[-1]), 1), "status": "pending"}
                ev("app", user, "prediction", now, now, pred)
                preds_rows.append({"prediction_id": pred["prediction_id"], "window_start": pd.Timestamp(curve[0]["t"]),
                                   "window_end": pd.Timestamp(curve[-1]["t"])})
                add_grade(pm, user, {**pred, "cgm_only_curve": cgm_curve}, c, now + DELAY)
            now += pd.Timedelta(minutes=args.nowcast_every_min)

    # a teammate on the phone: a 10-minute walk after the first participant's breakfast, plus one chat turn
    cadence = [98, 104, 108, 110, 107, 105, 109, 111, 106, 103]
    steps = [{"value": v, "start": iso(walk_start + pd.Timedelta(minutes=i)),
              "end": iso(walk_start + pd.Timedelta(minutes=i + 1))} for i, v in enumerate(cadence)]
    for s in steps:
        ev("iphone", "u_demo", "steps", pd.Timestamp(s["start"]), pd.Timestamp(s["end"]), s)
    walk = summarize_walk(steps, walk_effect=model.walk_effect(None, 10, "moderate"))
    ended = pd.Timestamp(walk["ended_at"])
    ev("iphone", "u_demo", "walk", ended, ended, walk)
    chat_at = walk_start - pd.Timedelta(minutes=25)
    ev("app", "u_demo", "chat", chat_at, chat_at, {"role": "user", "text": "two waffles and coffee"})

    # flush into 5-second batches (replay minutes per batch = 5 s x speed), one file per source per batch
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for f in list(out.glob("*.jsonl")) + list(out.glob("EXPECTED.json")):
        f.unlink()
    df = pd.DataFrame(events)
    rel = pd.to_datetime(df["released_at"], utc=True, format="ISO8601")
    batch_sec = 5.0 * args.speed
    df["batch"] = ((rel - w0).dt.total_seconds() // batch_sec).astype(int)
    wall0 = pd.Timestamp(args.wall_start)
    seq = 0
    for b, grp in df.sort_values(["batch", "released_at", "event_id"]).groupby("batch"):
        stamp = (wall0 + pd.Timedelta(seconds=5 * int(b))).strftime("%Y%m%dT%H%M%S")
        for source, g2 in grp.groupby("source", sort=True):
            seq += 1
            with open(out / f"{stamp}_{source}_{seq:04d}.jsonl", "w", encoding="utf-8", newline="\n") as fh:
                for rec in g2.drop(columns="batch").to_dict(orient="records"):
                    fh.write(json.dumps(rec, default=_json_default, allow_nan=False) + "\n")

    grades = pd.DataFrame(grade_rows)
    preds = pd.DataFrame(preds_rows)
    meals = pd.DataFrame(meal_rows)
    expected = {
        "generated_by": "data/scripts/make_test_events.py",
        "note": "Pipeline test fixture: a few replay hours for a few participants. These numbers test the pipeline; they are not results.",
        "model_by_user": folds,
        "walk_effect_graded_false": int((~grades["walk_effect_graded"].fillna(True).astype(bool)).sum()) if len(grades) else 0,
        "replay": {"date": args.date, "tz": args.tz, "replay_day": replay_day, "participants": args.participants,
                   "released_window_utc": [iso(w0), iso(w1)], "speed": args.speed, "cgm_delay_min": 60},
        "files": seq, "events": len(df),
        "by_kind": {k: int(v) for k, v in df["kind"].value_counts().sort_index().items()},
        "by_user": {k: int(v) for k, v in df["user_id"].value_counts().sort_index().items()},
        "expected_rows": {
            "stream_bronze_events": len(df),
            "stream_silver_cgm": int((df.kind == "cgm").sum()),
            "stream_silver_meals": int((df.kind == "meal").sum()),
            "stream_silver_predictions": int((df.kind == "prediction").sum()),
            "stream_silver_grades": int((df.kind == "grade").sum()),
            "stream_silver_cards": int((df.kind == "card").sum()),
            "stream_gold_fleet": int(df.loc[df.kind == "cgm", "user_id"].nunique()),
        },
        "expected_gold_accuracy": gold_accuracy(grades, preds, meals) if len(grades) else [],
    }
    (out / "EXPECTED.json").write_text(json.dumps(expected, indent=2, default=_json_default) + "\n", encoding="utf-8")
    print(f"{len(df)} events in {seq} files, replay day {replay_day}, released {iso(w0)} to {iso(w1)} -> {out}")
    print("kinds:", expected["by_kind"])
    for r in expected["expected_gold_accuracy"]:
        if r["user_id"] == "ALL":
            print("gold:", r)
    for g in grade_rows[:4]:
        print("grade:", g["kind"], g["message"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
