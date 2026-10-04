"""Contract tests on the real engine: Data's gummi_model plus the cached replay tables, landing disabled.

Every response validates against the CONTRACT.md 1.3 mirrors in gummi_api.models (extra fields fail). The replay
clock is fast-forwarded by moving its wall anchor and ticking the engine directly.
Needs backend/.cache (gummi_model_v1/ and replay_*.parquet): run scripts/fetch_cache.py once.
"""
import os
import time
from pathlib import Path

CACHE = Path(__file__).resolve().parents[1] / ".cache"
os.environ.setdefault("GUMMI_LANDING_ENABLED", "false")
os.environ.setdefault("GUMMI_REPLAY_SOURCE", "cache")
os.environ.setdefault("GUMMI_MODEL_DIR", str(CACHE / "gummi_model_v1"))

import pytest  # noqa: E402

if not (CACHE / "replay_cgm.parquet").exists() or not (CACHE / "gummi_model_v1" / "model.npz").exists():
    pytest.skip("run scripts/fetch_cache.py first", allow_module_level=True)

from fastapi.testclient import TestClient  # noqa: E402

from gummi_api import models as M  # noqa: E402
from gummi_api.engine.engine import engine  # noqa: E402
from gummi_api.main import app  # noqa: E402
from gummi_api.stream.producer import clock  # noqa: E402

H = {"X-User-Id": "u_test"}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        for _ in range(120):
            if c.get("/api/v1/health").json()["status"] == "ok":
                break
            time.sleep(0.5)
        assert engine.ready, engine.load_error
        yield c


def ok(r, status=200):
    assert r.status_code == status, r.text
    assert r.headers["X-Gummi-Mode"] in ("mock", "live")
    return r.json()


def advance(replay_minutes: int) -> None:
    for _ in range(replay_minutes):
        clock.anchor_wall -= 60.0 / clock.speed
        engine.tick()


def test_health(client):
    h = M.Health.model_validate(ok(client.get("/api/v1/health")))
    assert h.status == "ok" and h.mode == "live"


def test_state_without_follow(client):
    s = M.State.model_validate(ok(client.get("/api/v1/state", headers={"X-User-Id": "u_nobody"})))
    assert s.gummi_view is None and s.confirmed == [] and s.acting_as is None


def test_follow_and_replay_day(client):
    s = M.State.model_validate(ok(client.post("/api/v1/follow", json={"user_id": "p_012"}, headers=H)))
    assert s.acting_as == "p_012" and s.gummi_view is not None
    assert s.confirmed[-1].t < s.estimate[0].t and s.estimate[-1].t < s.forecast[-1].t
    assert 55 <= s.gummi_view.minutes_since_confirmed <= 70, "the Dexcom delay"
    assert client.post("/api/v1/follow", json={"user_id": "p_015"}, headers=H).status_code == 404   # D-37

    st = M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/start", json={"speed": 60})))
    assert st.running and st.replay_clock == "day6T05:00" and st.participants == 15     # D-62 default start
    s = M.State.model_validate(ok(client.get("/api/v1/state", headers=H)))
    assert s.replay_now and s.upcoming_due, "acting as p_012 with breakfast due within 6 h"
    due = s.upcoming_due[0]

    advance(60)                                    # the 05:54 standardized breakfast comes due
    cards = ok(client.get("/api/v1/feed", headers=H))["cards"]
    due_card = next(c for c in cards if c["type"] == "meal_due" and c["actions"])
    assert due_card["actions"][0]["due_id"] == due.due_id
    meal = M.Meal.model_validate(ok(client.post(f"/api/v1/meals/due/{due.due_id}/log", headers=H)))
    assert meal.source == "replay_due" and meal.is_standard_breakfast and meal.prediction_id
    again = client.post(f"/api/v1/meals/due/{due.due_id}/log", headers=H)
    assert again.status_code == 409 and again.json()["error"]["code"] == "due_already_logged"
    cards = {c["card_id"]: c for c in ok(client.get("/api/v1/feed", headers=H))["cards"]}
    assert cards[due_card["card_id"]]["actions"] == [] and cards[due_card["card_id"]]["body"].endswith("Logged.")

    pred = next(p for p in ok(client.get("/api/v1/predictions?status=pending", headers=H))["predictions"]
                if p["prediction_id"] == meal.prediction_id)
    p = M.Prediction.model_validate(pred)
    assert p.cgm_only_peak_mg_dl is not None and p.predicted_curve

    advance(200)                                   # window closes, readings arrive an hour later
    grades = ok(client.get("/api/v1/grades", headers=H))["grades"]
    g = M.Grade.model_validate(next(x for x in grades if x["prediction_id"] == meal.prediction_id))
    assert g.cgm_only_mae_mg_dl is not None and g.message.startswith("I predicted")
    for x in grades:
        M.Grade.model_validate(x)
    for c in ok(client.get("/api/v1/feed", headers=H))["cards"]:
        M.StoryCard.model_validate(c)
    s = M.State.model_validate(ok(client.get("/api/v1/state", headers=H)))
    assert s.today.gummi_mae_mg_dl is not None and s.today.meals >= 1


def test_simulate(client):
    s = M.Simulation.model_validate(ok(client.post("/api/v1/simulate", headers=H, json={"items": [{"name": "cookie"}]})))
    assert s.alternatives[1].effect_source in ("literature", "your data") and s.peak_mg_dl > 0
    r = client.post("/api/v1/simulate", headers={"X-User-Id": "u_nobody"}, json={"items": [{"name": "cookie"}]})
    assert r.status_code == 409 and r.json()["error"]["code"] == "no_cgm_data"


def test_fleet_and_stream_controls(client):
    f = M.Fleet.model_validate(ok(client.get("/api/v1/fleet")))
    assert len(f.entries) == 15 and "p_015" not in {e.user_id for e in f.entries}
    assert f.fleet_gummi_mae_mg_dl is not None and f.fleet_cgm_only_mae_mg_dl is not None
    assert M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/pause"))).paused
    assert M.State.model_validate(ok(client.get("/api/v1/state", headers=H))).upcoming_due == []
    assert not M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/resume"))).paused
    assert M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/speed", json={"speed": 10}))).speed == 10
    assert client.post("/api/v1/stream/start", json={"start_at": "tuesday"}).status_code == 422


def test_walk_overlay(client):
    ok(client.post("/api/v1/events", headers=H, json={"type": "walk_started"}))
    ok(client.post("/api/v1/events", headers=H, json={"type": "walk_completed", "at": "2026-10-03T12:20:00Z",
                                                      "started_at": "2026-10-03T12:08:00Z", "steps": 1300,
                                                      "cadence_spm": 108}))
    w = M.WalkSummary.model_validate(ok(client.get("/api/v1/walks/latest", headers=H)))
    assert (w.minutes, w.steps, w.cadence_spm) == (12, 1300, 108)
    feed = ok(client.get("/api/v1/feed", headers=H))["cards"]
    assert feed[0]["type"] == "walk_summary" and "replayed day" in feed[0]["body"]


def test_teammate_meal_lifecycle(client):
    h = {"X-User-Id": "u_solo"}
    m = M.Meal.model_validate(ok(client.post("/api/v1/meals", headers=h, json={
        "items": [{"name": "waffle", "quantity": 2}, {"name": "black coffee"}], "source": "manual"})))
    assert m.totals.carbs_g == 50.0 and m.items[0].nutrition_source == "seed" and m.prediction_id is None
    e = M.Meal.model_validate(ok(client.patch(f"/api/v1/meals/{m.meal_id}", headers=h,
                                              json={"items": [{"name": "waffle", "quantity": 1}]})))
    assert e.totals.carbs_g == 25.0
    assert ok(client.delete(f"/api/v1/meals/{m.meal_id}", headers=h)) == {"deleted": True}
    assert client.delete(f"/api/v1/meals/{m.meal_id}", headers=h).json()["error"]["code"] == "not_found"


def _sse(text: str) -> list[tuple[str, dict]]:
    import json
    out = []
    for block in text.strip().split("\n\n"):
        lines = dict(line.split(": ", 1) for line in block.split("\n") if ": " in line and not line.startswith(":"))
        if "event" in lines:
            out.append((lines["event"], json.loads(lines["data"])))
    return out


@pytest.mark.parametrize("uid,message,card_type", [("u_solo", "I just had two waffles and a black coffee", "meal_saved"),
                                                    ("u_test", "can I eat a cookie now?", "simulation"),
                                                    ("u_test", "how am I doing?", "gummi_view")])
def test_chat(client, uid, message, card_type):
    events = _sse(client.post("/api/v1/chat", headers={"X-User-Id": uid}, json={"message": message}).text)
    kinds = [e for e, _ in events]
    assert kinds[0] == "mood" and kinds[-1] == "done" and "token" in kinds
    cards = [d for e, d in events if e == "card"]
    assert cards and cards[0]["card_type"] == card_type
    {"meal_saved": M.Meal, "simulation": M.Simulation, "gummi_view": M.GummiView}[card_type].model_validate(cards[0]["payload"])


def test_profile_engine_errors(client):
    p = M.Profile.model_validate(ok(client.put("/api/v1/profile", headers=H, json={"high_line_mg_dl": 150})))
    assert p.high_line_mg_dl == 150
    e = ok(client.get("/api/v1/engine"))
    assert e["ready"] and e["predictions"] > 0 and e["grades"] > 0
    M.DexcomStatus.model_validate(ok(client.get("/api/v1/dexcom/status", headers=H)))
    assert "<title>Gummi Fleet</title>" in client.get("/api/v1/fleet/view").text
    r = client.get("/api/v1/state", headers={"X-User-Id": "DROP TABLE"})
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_request"
    r = client.put("/api/v1/health")
    assert r.status_code == 405 and r.json()["error"]["code"] == "method_not_allowed"
    assert ok(client.post("/api/v1/follow", json={"user_id": None}, headers=H))["acting_as"] is None
