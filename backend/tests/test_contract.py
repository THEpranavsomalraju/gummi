"""Every route's response validates against the CONTRACT.md 1.2 mirrors in gummi_api.models (extra fields fail)."""
import os

os.environ.setdefault("GUMMI_LANDING_ENABLED", "false")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from gummi_api import models as M  # noqa: E402
from gummi_api.main import app  # noqa: E402

H = {"X-User-Id": "u_test"}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def ok(r, status=200):
    assert r.status_code == status, r.text
    assert r.headers["X-Gummi-Mode"] in ("mock", "live")
    return r.json()


def test_health(client):
    M.Health.model_validate(ok(client.get("/api/v1/health")))


def test_state_and_follow(client):
    s = M.State.model_validate(ok(client.get("/api/v1/state", headers=H)))
    assert s.confirmed[-1].t < s.estimate[0].t < s.forecast[0].t, "confirmed, then estimate, then forecast"
    assert 55 <= s.gummi_view.minutes_since_confirmed <= 65
    assert s.estimate[-1].band_high_mg_dl - s.estimate[-1].band_low_mg_dl > s.estimate[0].band_high_mg_dl - s.estimate[0].band_low_mg_dl
    f = M.State.model_validate(ok(client.post("/api/v1/follow", json={"user_id": "p_012"}, headers=H)))
    assert f.following == f.acting_as == "p_012"
    assert client.post("/api/v1/follow", json={"user_id": "p_015"}, headers=H).status_code == 404   # D-37


def test_feed_predictions_grades(client):
    for c in ok(client.get("/api/v1/feed", headers=H))["cards"]:
        M.StoryCard.model_validate(c)
    for p in ok(client.get("/api/v1/predictions?status=pending", headers=H))["predictions"]:
        assert M.Prediction.model_validate(p).status == "pending"
    for g in ok(client.get("/api/v1/grades", headers=H))["grades"]:
        M.Grade.model_validate(g)


def test_meal_lifecycle(client):
    m = M.Meal.model_validate(ok(client.post("/api/v1/meals", headers=H, json={
        "items": [{"name": "waffle", "quantity": 2}, {"name": "black coffee"}], "source": "manual"})))
    assert m.totals.carbs_g == 50.0 and m.items[0].nutrition_source == "seed"
    edited = M.Meal.model_validate(ok(client.patch(f"/api/v1/meals/{m.meal_id}", headers=H,
                                                   json={"items": [{"name": "waffle", "quantity": 1}]})))
    assert edited.totals.carbs_g == 25.0 and edited.prediction_id != m.prediction_id
    assert any(x["meal_id"] == m.meal_id for x in ok(client.get("/api/v1/meals", headers=H))["meals"])
    assert ok(client.delete(f"/api/v1/meals/{m.meal_id}", headers=H)) == {"deleted": True}
    assert client.delete(f"/api/v1/meals/{m.meal_id}", headers=H).json()["error"]["code"] == "not_found"


def test_due_meal(client):
    m = M.Meal.model_validate(ok(client.post("/api/v1/meals/due/d_2/log", headers=H)))
    assert m.source == "replay_due"


def test_simulate(client):
    s = M.Simulation.model_validate(ok(client.post("/api/v1/simulate", headers=H,
                                                   json={"items": [{"name": "cookie"}], "eat_at": None})))
    assert s.alternatives[1].effect_source == "literature"


def test_vitals_events_walk(client):
    assert ok(client.post("/api/v1/vitals", headers=H, json={"samples": [
        {"type": "steps", "value": 112, "start": "2026-10-03T12:00:00Z", "end": "2026-10-03T12:05:00Z"}]})) == {"accepted": 1}
    assert ok(client.post("/api/v1/events", headers=H, json={"type": "walk_started", "at": "2026-10-03T12:00:00Z"}))["ok"]
    assert ok(client.post("/api/v1/events", headers=H, json={"type": "walk_completed", "at": "2026-10-03T12:11:00Z"}))["ok"]
    w = M.WalkSummary.model_validate(ok(client.get("/api/v1/walks/latest", headers=H)))
    assert w.minutes == 11


def test_profile(client):
    p = M.Profile.model_validate(ok(client.put("/api/v1/profile", headers=H, json={"high_line_mg_dl": 150})))
    assert p.high_line_mg_dl == 150
    M.Profile.model_validate(ok(client.get("/api/v1/profile", headers=H)))


def test_stream_controls_and_fleet(client):
    s = M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/start", json={"speed": 60, "start_at": "day6T06:00"})))
    assert s.running and s.replay_clock == "day6T06:00" and s.participants == 15
    assert M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/pause"))).paused
    assert not M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/resume"))).paused
    assert M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/speed", json={"speed": 10}))).speed == 10
    st = M.State.model_validate(ok(client.get("/api/v1/state", headers=H)))
    assert st.upcoming_due, "acting as p_012 with the stream running"
    f = M.Fleet.model_validate(ok(client.get("/api/v1/fleet")))
    assert len(f.entries) == 15 and "p_015" not in {e.user_id for e in f.entries}
    assert not M.StreamStatus.model_validate(ok(client.post("/api/v1/stream/stop"))).running
    assert client.post("/api/v1/stream/start", json={"start_at": "tuesday"}).status_code == 422


def test_dexcom_engine_fleet_view(client):
    M.DexcomStatus.model_validate(ok(client.get("/api/v1/dexcom/status", headers=H)))
    assert "events" in ok(client.get("/api/v1/engine"))
    assert "<title>Gummi Fleet</title>" in client.get("/api/v1/fleet/view").text


def _sse(text: str) -> list[tuple[str, str]]:
    import json
    out = []
    for block in text.strip().split("\n\n"):
        lines = dict(line.split(": ", 1) for line in block.split("\n") if ": " in line and not line.startswith(":"))
        if "event" in lines:
            out.append((lines["event"], json.loads(lines["data"])))
    return out


@pytest.mark.parametrize("message,card_type", [("I just had two waffles and a black coffee", "meal_saved"),
                                                ("can I eat a cookie now?", "simulation"),
                                                ("how am I doing?", "gummi_view")])
def test_chat(client, message, card_type):
    events = _sse(client.post("/api/v1/chat", headers={"X-User-Id": "u_chat"}, json={"message": message}).text)
    kinds = [e for e, _ in events]
    assert kinds[0] == "mood" and kinds[-1] == "done" and "token" in kinds
    cards = [d for e, d in events if e == "card"]
    assert cards and cards[0]["card_type"] == card_type
    payload = cards[0]["payload"]
    {"meal_saved": M.Meal, "simulation": M.Simulation, "gummi_view": M.GummiView}[card_type].model_validate(payload)


def test_errors(client):
    r = client.get("/api/v1/state", headers={"X-User-Id": "DROP TABLE"})
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_request"


def test_contract_1_3(client):
    h = {"X-User-Id": "u_v13"}
    s = M.State.model_validate(ok(client.post("/api/v1/follow", json={"user_id": "p_012"}, headers=h)))
    assert s.stream is not None and s.replay_now is None, "stream stopped -> replay_now null"
    ok(client.post("/api/v1/stream/start", json={}))
    s = M.State.model_validate(ok(client.get("/api/v1/state", headers=h)))
    assert s.replay_now and s.stream.running and s.stream.replay_clock.startswith("day6T05:0"), "D-40 default start"
    m = M.Meal.model_validate(ok(client.post("/api/v1/meals/due/d_1/log", headers=h)))
    assert m.source == "replay_due" and m.is_standard_breakfast is False
    again = client.post("/api/v1/meals/due/d_1/log", headers=h)
    assert again.status_code == 409 and again.json()["error"]["code"] == "due_already_logged"
    resolved = [c for c in ok(client.get("/api/v1/feed", headers=h))["cards"] if c["type"] == "meal_due" and not c["actions"]]
    assert resolved and resolved[0]["body"].endswith("Logged.")
    ok(client.post("/api/v1/stream/stop"))
    assert M.State.model_validate(ok(client.post("/api/v1/follow", json={"user_id": None}, headers=h))).acting_as is None
    ok(client.post("/api/v1/events", headers=h, json={"type": "walk_completed", "at": "2026-10-03T12:20:00Z",
                                                      "started_at": "2026-10-03T12:08:00Z", "steps": 1300, "cadence_spm": 108}))
    w = M.WalkSummary.model_validate(ok(client.get("/api/v1/walks/latest", headers=h)))
    assert (w.minutes, w.steps, w.cadence_spm) == (12, 1300, 108)
    r = client.put("/api/v1/health")
    assert r.status_code == 405 and r.json()["error"]["code"] == "method_not_allowed"
