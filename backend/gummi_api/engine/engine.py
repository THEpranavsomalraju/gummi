"""Replay engine: hot state per replayed participant, predictions, three-way grading, due meals, walk alerts.

One tick per second releases what the replay clock has reached:
  CGM readings become visible delay_minutes after their event time (the Dexcom delay),
  meals release at their event time: logged at once (source "replay") unless a teammate acts as that participant,
    in which case they come due as meal_due cards and auto-log after 10 replay minutes (D-27),
  every meal gets a prediction (Gummi, CGM-only, last value), every participant a nowcast once per replay hour,
  predictions are graded once confirmed data covers the window (D-26: always through model.for_user),
  followed participants get walk alerts when the forecast crosses the high line (cooldown 45 replay minutes).
Everything lands in the landing volume through the writer, off the request path.
"""
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from .. import config
from ..live.broadcaster import broadcaster
from ..state.hot_store import store
from ..stream.landing_writer import landing
from ..stream.producer import clock
from ..util import iso, iso_utc, new_id, r1, utcnow

log = logging.getLogger("gummi.engine")
MACROS = ("carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g")
GRADE_KEYS = ("prediction_id", "kind", "points", "gummi_mae_mg_dl", "cgm_only_mae_mg_dl", "last_value_mae_mg_dl",
              "gummi_peak_error_mg_dl", "within_band_pct", "walk_effect_graded", "gummi_beats_cgm_only",
              "gummi_beats_last_value", "message")


@dataclass
class Subject:
    pid: str
    model: object
    cgm_off: np.ndarray
    cgm_val: np.ndarray
    meal_rows: list[dict]
    ci: int = 0                                   # next reading to release
    mi: int = 0                                   # next meal to release
    conf_t: list = field(default_factory=list)    # released readings (UTC timestamps)
    conf_v: list = field(default_factory=list)
    meals: list[dict] = field(default_factory=list)          # logged Meals (contract shape)
    meal_inputs: list[dict] = field(default_factory=list)    # model input rows, keyed by meal_id
    predictions: dict = field(default_factory=dict)
    grades: list[dict] = field(default_factory=list)
    personal: dict | None = None
    next_nowcast: float = 0.0
    last_walk_alert: float = -1e9
    walk_checked_version: int = -1
    pending: set = field(default_factory=set)     # prediction ids not graded yet
    personal_busy: bool = False
    version: int = 0                              # bumps on every change, drives caches and state pushes
    _cache: dict = field(default_factory=dict)

    def cgm_df(self) -> pd.DataFrame:
        key = ("cgm", len(self.conf_t))
        if self._cache.get("cgm_key") != key:
            self._cache["cgm"] = pd.DataFrame({"t": pd.to_datetime(self.conf_t, utc=True), "glucose_mg_dl": self.conf_v})
            self._cache["cgm_key"] = key
        return self._cache["cgm"]

    def meals_df(self) -> pd.DataFrame:
        if not self.meal_inputs:
            return pd.DataFrame(columns=["eaten_at", *MACROS])
        return pd.DataFrame(self.meal_inputs)[["eaten_at", *MACROS]]


class Engine:
    def __init__(self):
        self.model = None
        self.cgm: pd.DataFrame | None = None
        self.meal_table: pd.DataFrame | None = None
        self.subjects: dict[str, Subject] = {}
        self.dues: dict[str, dict] = {}
        self.ready = False
        self.load_error: str | None = None
        self.counters = {"ticks": 0, "predictions": 0, "grades": 0, "meals": 0, "walk_alerts": 0,
                         "last_tick_ms": 0.0, "max_tick_ms": 0.0}
        self._last_r: float | None = None
        self._personal_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="personal")

    # ---------- startup ----------
    def load(self) -> None:
        from .model_adapter import load_model
        from .replay_data import load_replay
        try:
            self.model = load_model()
            self.cgm, self.meal_table = load_replay()
            self.ready = True
            log.info("engine ready: %s, %d readings, %d meals", self.model.version, len(self.cgm), len(self.meal_table))
        except Exception as e:  # noqa: BLE001
            self.load_error = f"{type(e).__name__}: {e}"
            log.exception("engine load failed")

    def profile_for(self, pid: str) -> dict:
        return {"timezone": config.TIMEZONE, "high_line_mg_dl": config.HIGH_LINE, "low_line_mg_dl": config.LOW_LINE}

    def ctx(self, s: Subject):
        from gummi_model import UserContext
        return UserContext(s.pid, self.profile_for(s.pid), s.cgm_df(), s.meals_df(), None, s.personal)

    # ---------- replay control ----------
    def start(self, start_r: float) -> None:
        """Build every participant's hot state as of start_r: history already released, no events for it."""
        self.subjects, self.dues = {}, {}
        self.counters.update({"predictions": 0, "grades": 0, "meals": 0, "walk_alerts": 0, "max_tick_ms": 0.0})
        for i, pid in enumerate(config.PARTICIPANTS):
            c = self.cgm[self.cgm.user_id == pid]
            m = self.meal_table[self.meal_table.user_id == pid].to_dict("records")
            s = Subject(pid, self.model.for_user(pid), c.t_offset_min.to_numpy(float), c.glucose_mg_dl.to_numpy(float), m)
            # stagger nowcasts across participants so one tick never runs 15 of them
            s.next_nowcast = start_r + 4 * (i % 15)
            self.subjects[pid] = s
            self._release(s, start_r, emit=False)
        self._last_r = start_r

    def _due_followers(self, pid: str) -> list[str]:
        return [u.user_id for u in store.users.values() if u.following == pid]

    def _release(self, s: Subject, now_r: float, emit: bool = True) -> int:
        n = 0
        visible = now_r - clock.delay_minutes
        released_at = iso_utc(utcnow())
        while s.ci < len(s.cgm_off) and s.cgm_off[s.ci] <= visible:
            t = clock.replay_to_wall(s.cgm_off[s.ci])
            s.conf_t.append(pd.Timestamp(t).tz_convert("UTC"))
            s.conf_v.append(float(s.cgm_val[s.ci]))
            if emit:
                landing.enqueue({"source": "replay", "user_id": s.pid, "kind": "cgm", "t": iso_utc(t),
                                 "released_at": released_at, "payload": {"glucose_mg_dl": float(s.cgm_val[s.ci])}})
                n += 1
            s.ci += 1
        while s.mi < len(s.meal_rows) and s.meal_rows[s.mi]["t_offset_min"] <= now_r:
            row = s.meal_rows[s.mi]
            s.mi += 1
            followers = self._due_followers(s.pid) if emit else []
            if followers:
                self._make_due(s, row, followers)
            else:
                self.log_meal(s, self._replay_meal(row), row["t_offset_min"], "replay", predict=emit, emit=emit)
                n += emit
        if n or not emit:
            s.version += 1
        return n

    # ---------- meals and predictions ----------
    @staticmethod
    def _replay_meal(row: dict) -> dict:
        names = [x.strip() for x in str(row["items"]).split("|") if x.strip()]
        macros = {k: r1(row[k]) if pd.notna(row[k]) else 0.0 for k in MACROS}
        cal = r1(row["calories"]) if pd.notna(row["calories"]) else 0.0
        item = {"name": ", ".join(names) or "Meal", "quantity": 1.0, "unit": "meal", **macros, "calories": cal,
                "nutrition_source": "dataset", "editable": True}
        return {"meal_id": f"m_{row['meal_id']}", "items": [item], "is_standard_breakfast": bool(row["is_standard_breakfast"])}

    def log_meal(self, s: Subject, meal: dict, eaten_r: float, source: str, predict: bool = True,
                 emit: bool = True) -> dict:
        eaten_at = clock.replay_to_wall(eaten_r)
        totals = {k: r1(sum(i[k] for i in meal["items"])) for k in (*MACROS, "calories")}
        full = {"meal_id": meal["meal_id"], "eaten_at": iso(eaten_at), "source": source, "items": meal["items"],
                "totals": totals, "is_standard_breakfast": meal.get("is_standard_breakfast", False), "prediction_id": None}
        s.meals.append(full)
        s.meal_inputs.append({"meal_id": full["meal_id"], "eaten_at": pd.Timestamp(eaten_at).tz_convert("UTC"),
                              **{k: totals[k] for k in MACROS}})
        s.version += 1
        self.counters["meals"] += emit
        if predict and len(s.conf_t) >= 3:
            pred = self._meal_prediction(s, full, eaten_r)
            full["prediction_id"] = pred["prediction_id"]
        if emit:
            t = iso_utc(eaten_at)
            landing.enqueue({"source": "replay" if source.startswith("replay") else "app", "user_id": s.pid,
                             "kind": "meal", "t": t, "released_at": iso_utc(utcnow()), "payload": full})
        return full

    def _window(self, pts: list[dict], start, end) -> list[dict]:
        a, b = iso_utc(start), iso_utc(end)
        return [p for p in pts if a <= p["t"] <= b]

    def _meal_prediction(self, s: Subject, meal: dict, eaten_r: float) -> dict:
        now_r = clock.now() if clock.now() is not None else eaten_r
        now = clock.replay_to_wall(max(now_r, eaten_r))
        start, end = clock.replay_to_wall(eaten_r), clock.replay_to_wall(eaten_r + 120)
        ctx = self.ctx(s)
        m = s.model
        curve = self._window(m.estimate_gap(ctx, now) + m.forecast(ctx, now, 120), start, end)
        cgm_only = self._window(m.cgm_only_forecast(ctx, now, 120, include_gap=True), start, end)
        about = meal["items"][0]["name"] if len(meal["items"]) == 1 else ", ".join(i["name"] for i in meal["items"][:2])
        pid = meal["meal_id"].replace("m_", "pr_", 1) if meal["meal_id"].startswith("m_") else new_id("pr")
        return self._store_prediction(s, {
            "prediction_id": pid, "kind": "meal", "made_at": iso(now), "about": about.lower(), "meal_id": meal["meal_id"],
            "window_start": iso(start), "window_end": iso(end),
            "predicted_peak_mg_dl": max((p["glucose_mg_dl"] for p in curve), default=s.conf_v[-1]),
            "predicted_curve": curve,
            "cgm_only_peak_mg_dl": max((p["glucose_mg_dl"] for p in cgm_only), default=None),
            "last_value_peak_mg_dl": r1(s.conf_v[-1]), "status": "pending"}, cgm_only)

    def _nowcast(self, s: Subject, now_r: float) -> None:
        now = clock.replay_to_wall(now_r)
        ctx = self.ctx(s)
        curve = s.model.estimate_gap(ctx, now)
        if not curve:
            return
        cgm_only = s.model.cgm_only_forecast(ctx, now, minutes=0, include_gap=True)
        self._store_prediction(s, {
            "prediction_id": new_id(f"pr_{s.pid[2:]}-now"), "kind": "nowcast", "made_at": iso(now),
            "about": "the last hour", "meal_id": None, "window_start": curve[0]["t"], "window_end": curve[-1]["t"],
            "predicted_peak_mg_dl": max(p["glucose_mg_dl"] for p in curve), "predicted_curve": curve,
            "cgm_only_peak_mg_dl": max((p["glucose_mg_dl"] for p in cgm_only), default=None),
            "last_value_peak_mg_dl": r1(s.conf_v[-1]), "status": "pending"}, cgm_only)

    def _store_prediction(self, s: Subject, pred: dict, cgm_only_curve: list[dict]) -> dict:
        s.predictions[pred["prediction_id"]] = {**pred, "_cgm_only_curve": cgm_only_curve,
                                                "_end_utc": iso_utc(pd.Timestamp(pred["window_end"]))}
        s.pending.add(pred["prediction_id"])
        self.counters["predictions"] += 1
        landing.enqueue({"source": "app", "user_id": s.pid, "kind": "prediction", "t": iso_utc(pd.Timestamp(pred["made_at"])),
                         "released_at": iso_utc(utcnow()), "payload": pred})
        return pred

    @staticmethod
    def public_prediction(p: dict) -> dict:
        return {k: v for k, v in p.items() if not k.startswith("_")}

    # ---------- grading ----------
    def _grade_due(self, s: Subject, now_r: float) -> None:
        if not s.conf_t:
            return
        through = iso_utc(s.conf_t[-1])
        for pid in [x for x in s.pending if s.predictions.get(x, {}).get("_end_utc", "~") <= through]:
            s.pending.discard(pid)
            p = s.predictions.get(pid)
            if p is None or p["status"] != "pending":
                continue
            walks = self._overlay_walks(s.pid)
            g = s.model.grade({**p, "cgm_only_curve": p["_cgm_only_curve"]}, s.cgm_df(), overlay_walks=walks or None)
            p["status"] = "graded"
            s.version += 1
            if g.get("status") != "graded":
                continue
            grade = {"grade_id": p["prediction_id"].replace("pr_", "g_", 1), "graded_at": iso(clock.replay_to_wall(now_r)),
                     **{k: g.get(k) for k in GRADE_KEYS}}
            grade["prediction_id"] = p["prediction_id"]
            s.grades.append(grade)
            self.counters["grades"] += 1
            landing.enqueue({"source": "app", "user_id": s.pid, "kind": "grade", "t": iso_utc(clock.replay_to_wall(now_r)),
                             "released_at": iso_utc(utcnow()), "payload": {**grade, "status": "graded",
                             "gummi_bias_mg_dl": g.get("gummi_bias_mg_dl"), "actual_peak_mg_dl": g.get("actual_peak_mg_dl"),
                             "actual_peak_at": g.get("actual_peak_at")}})
            if p["kind"] == "meal":
                self._update_personal_async(s)
            self._announce_grade(s, p, grade, g, now_r)

    def _update_personal_async(self, s: Subject) -> None:
        """update_personal refits on the person's closed meals (~0.5 s), so it runs off the tick in one worker thread."""
        if s.personal_busy:
            return
        s.personal_busy = True
        ctx, grades = self.ctx(s), list(s.grades)

        def work():
            try:
                s.personal = s.model.update_personal(ctx, grades)
                s.version += 1
            except Exception:  # noqa: BLE001 (personal layer is best effort)
                log.exception("update_personal failed for %s", s.pid)
            finally:
                s.personal_busy = False
        self._personal_pool.submit(work)

    def _overlay_walks(self, pid: str) -> list[dict]:
        out = []
        for u in store.users.values():
            if u.following == pid:
                out.extend(u.overlay_walks)
        return out

    def _announce_grade(self, s: Subject, p: dict, grade: dict, g: dict, now_r: float) -> None:
        from ..state import cards
        card = None
        if p["kind"] == "meal":
            peak = g.get("actual_peak_mg_dl")
            card = cards.card("meal_story", clock.replay_to_wall(now_r), f"Your {p['about']}, two hours later",
                              grade["message"], "proud" if grade["gummi_beats_cgm_only"] else "calm",
                              attachments={"grade": grade, "meal": next((m for m in s.meals if m["meal_id"] == p["meal_id"]), None),
                                           "curve": self._curve(s, p)},
                              actions=[{"label": "Ask Gummi why", "kind": "open_chat",
                                        "prompt": f"Why did I peak at {peak:.0f}?" if peak else "Why did I peak there?"}],
                              card_id=p["prediction_id"].replace("pr_", "c_", 1))
            landing.enqueue({"source": "app", "user_id": s.pid, "kind": "card", "t": iso_utc(clock.replay_to_wall(now_r)),
                             "released_at": iso_utc(utcnow()), "payload": {k: v for k, v in card.items() if k != "attachments"}})
        for uid in self._due_followers(s.pid):
            u = store.get(uid)
            u.grades.append(grade)
            broadcaster.publish(uid, "grade", grade)
            if grade["gummi_beats_cgm_only"]:
                u.proud_until = time.time() + config.PROUD_SECONDS
                broadcaster.publish(uid, "mood", {"mood": "proud"})
            if card:
                u.add_card(card)
                broadcaster.publish(uid, "card", card)

    def _curve(self, s: Subject, p: dict) -> list[dict]:
        a, b = iso_utc(pd.Timestamp(p["window_start"])), iso_utc(pd.Timestamp(p["window_end"]))
        return [{"t": iso(t), "glucose_mg_dl": v, "kind": "confirmed"}
                for t, v in zip(s.conf_t, s.conf_v) if a <= iso_utc(t) <= b]

    # ---------- due meals (acting-as, D-27) ----------
    def _make_due(self, s: Subject, row: dict, followers: list[str]) -> None:
        from ..state import cards
        due_id = f"d_{row['meal_id'].replace('-', '_')}"
        meal = self._replay_meal(row)
        name = store.display_name(s.pid)
        when = clock.replay_to_wall(row["t_offset_min"])
        label = cards.meal_label(when)
        card = cards.card("meal_due", when, f"{label} time for {name}", meal["items"][0]["name"], "calm",
                          actions=[{"label": "Log it", "kind": "log_due_meal", "due_id": due_id}],
                          card_id=f"c_{due_id}")
        self.dues[due_id] = {"due_id": due_id, "pid": s.pid, "row": row, "meal": meal, "due_r": row["t_offset_min"],
                             "logged": False, "card": card}
        for uid in followers:
            store.get(uid).add_card(card)
            broadcaster.publish(uid, "card", card)
        s.version += 1

    def log_due(self, due_id: str, source: str) -> dict | None:
        d = self.dues.get(due_id)
        if d is None:
            return None
        if d["logged"]:
            raise RuntimeError("due_already_logged")
        d["logged"] = True
        s = self.subjects[d["pid"]]
        meal = self.log_meal(s, d["meal"], d["due_r"], source)
        resolved = {**d["card"], "actions": [], "body": d["card"]["body"].rstrip(".") + ". Logged."}
        for uid in self._due_followers(s.pid):
            u = store.get(uid)
            u.add_card(resolved)
            broadcaster.publish(uid, "card", resolved)
            self._meal_logged_card(uid, s, meal)
        return meal

    def _meal_logged_card(self, uid: str, s: Subject, meal: dict) -> None:
        from ..state import cards
        pred = s.predictions.get(meal["prediction_id"]) if meal["prediction_id"] else None
        body = (f"I expect a peak near {pred['predicted_peak_mg_dl']:.0f} within two hours. That's Gummi's estimate, "
                f"and I'll grade it when the readings arrive." if pred else "Logged.")
        card = cards.card("meal_logged", pd.Timestamp(meal["eaten_at"]).to_pydatetime(), f"{meal['items'][0]['name']} logged",
                          body, "rising" if pred else "calm",
                          attachments={"meal": meal, **({"prediction": self.public_prediction(pred)} if pred else {})})
        store.get(uid).add_card(card)
        broadcaster.publish(uid, "card", card)

    def upcoming_due(self, pid: str | None) -> list[dict]:
        if not pid or pid not in self.subjects or not clock.running or clock.paused:
            return []
        now_r = clock.now()
        s = self.subjects[pid]
        from ..state import cards
        out = []
        for row in s.meal_rows[s.mi:]:
            if row["t_offset_min"] > now_r + config.UPCOMING_DUE_MIN:
                break
            real = clock.replay_to_real(row["t_offset_min"])
            meal = self._replay_meal(row)
            out.append({"due_id": f"d_{row['meal_id'].replace('-', '_')}", "due_at": iso(real),
                        "title": f"{cards.meal_label(clock.replay_to_wall(row['t_offset_min']))} time for {store.display_name(pid)}",
                        "body": meal["items"][0]["name"]})
        return out

    # ---------- walk alerts ----------
    def _walk_alert(self, s: Subject, now_r: float) -> None:
        from ..state import cards
        followers = self._due_followers(s.pid)
        if not followers or now_r - s.last_walk_alert < config.WALK_COOLDOWN_MIN or len(s.conf_t) < 3:
            return
        if s.walk_checked_version == s.version:      # only re-check when a reading or meal arrived
            return
        s.walk_checked_version = s.version
        now = clock.replay_to_wall(now_r)
        fc = s.model.forecast(self.ctx(s), now, 60)
        if not fc:
            return
        peak = max(fc, key=lambda p: p["glucose_mg_dl"])
        if peak["glucose_mg_dl"] < config.HIGH_LINE:
            return
        s.last_walk_alert = now_r
        self.counters["walk_alerts"] += 1
        eff = s.model.walk_effect(self.ctx(s), 10, "moderate")
        drop, src = eff.get("forecast_peak_drop_mg_dl", 0), eff.get("effect_source", "literature")
        minutes_to = max(5, round((pd.Timestamp(peak["t"]) - pd.Timestamp(now)).total_seconds() / 60))
        alert = {"alert_id": new_id("al"), "type": "walk_suggested",
                 "message": f"Gummi's forecast likely crosses {config.HIGH_LINE:.0f} in about {minutes_to} minutes. "
                            f"A 10 minute walk now could lower the peak by about {drop:.0f} mg/dL ({src}).",
                 "created_at": iso(now), "expires_at": iso(now + pd.Timedelta(minutes=30)),
                 "action": {"label": "Start walk", "kind": "start_walk", "minutes": 10}}
        card = cards.card("walk_suggested", now, "A short walk could help", alert["message"], "high",
                          attachments={"alert": alert})
        for uid in followers:
            u = store.get(uid)
            u.alert = alert
            u.add_card(card)
            broadcaster.publish(uid, "alert", alert)
            broadcaster.publish(uid, "card", card)

    # ---------- the tick ----------
    def tick(self) -> None:
        if not self.ready or not clock.running or clock.paused or not self.subjects:
            return
        t0 = time.perf_counter()
        now_r = clock.now()
        n = 0
        for s in self.subjects.values():
            n += self._release(s, now_r)
            if now_r >= s.next_nowcast and len(s.conf_t) >= 3:
                s.next_nowcast = now_r + config.NOWCAST_EVERY_MIN
                self._nowcast(s, now_r)
            self._grade_due(s, now_r)
            self._walk_alert(s, now_r)
        for due in self.dues.values():
            if not due["logged"] and now_r >= due["due_r"] + config.DUE_AUTOLOG_MIN:
                self.log_due(due["due_id"], "replay_auto")
        clock.count(n)
        self._last_r = now_r
        ms = (time.perf_counter() - t0) * 1000
        self.counters["ticks"] += 1
        self.counters["last_tick_ms"] = round(ms, 1)
        self.counters["max_tick_ms"] = round(max(ms, self.counters["max_tick_ms"]), 1)


engine = Engine()
