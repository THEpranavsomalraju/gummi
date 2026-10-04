"""Stage the 3-minute demo with one command, then trigger the live moment with a second.

    .venv/bin/python scripts/demo_stage.py stage [--redeploy]   # about 3 minutes, run before walking up
    .venv/bin/python scripts/demo_stage.py go                    # on stage: resume; the meal story lands about 15 s later
    .venv/bin/python scripts/demo_stage.py verify                # rehearsal: stage, go, and check every beat landed

Stage leaves the replay paused at day 4, 10:10 PM for p_012 (D-15). The 7:22 PM snack (dark chocolate chip, corn
cheese puffs) is logged and predicted, and its 2-hour grade is due once the 9:22 PM reading arrives an hour later.
Resuming at 60x lands the Meal Story ("I predicted 178 ... It was 186. CGM-only said 135, last value said 146"), the
grade and the proud mood about 12 replay minutes (12 s) later. The brownie walk nudge and the evening recap happen
during staging, so they're already in Activity.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = "https://dbc-0f92eb43-532a.cloud.databricks.com"
APP = "https://gummi-7474657192035402.aws.databricksapps.com/api/v1"
DEMO_USERS = ["u_mahil", "u_pranav"]
PID = "p_012"
STAGE_FROM, STAGE_TO = "day4T18:00", "day4T22:10"


def client(uid: str = "u_pranav") -> httpx.Client:
    env = dict(l.split("=", 1) for l in (ROOT / "secrets/iphone_sp.env").read_text().split("\n") if "=" in l)
    tok = httpx.post(f"{WORKSPACE}/oidc/v1/token", auth=(env["GUMMI_SP_CLIENT_ID"].strip(), env["GUMMI_SP_CLIENT_SECRET"].strip()),
                     data={"grant_type": "client_credentials", "scope": "all-apis"}, timeout=20).json()["access_token"]
    return httpx.Client(base_url=APP, headers={"Authorization": f"Bearer {tok}", "X-User-Id": uid}, timeout=60)


def minutes(label: str) -> int:
    d, hm = label[3:].split("T")
    h, m = hm.split(":")
    return (int(d) - 1) * 1440 + int(h) * 60 + int(m)


def step(msg: str) -> None:
    print(f"\n▸ {msg}", flush=True)


def stage(redeploy: bool) -> None:
    if redeploy:
        step("Redeploying the App")
        print(subprocess.run([str(ROOT / "scripts/deploy.sh")], capture_output=True, text=True).stdout.strip().splitlines()[-1])
    c = client()
    step("Waiting for /health")
    t0 = time.time()
    while time.time() - t0 < 300:
        try:
            if c.get("/health").json()["status"] == "ok":
                break
        except Exception:  # noqa: BLE001
            pass
        time.sleep(3)
    e = c.get("/engine").json()
    print(f"  ok · model {e['model_version']}")

    step("Dexcom sandbox (Mahil)")
    dx = client("u_mahil").get("/dexcom/status").json()
    print(f"  connected {dx['connected']}, data through {dx['data_through']}" if dx["connected"] else
          f"  NOT connected: open {APP}/dexcom/connect in the signed-in laptop browser, pick Mahil, Sandbox User - G7")

    step(f"Demo users follow {PID}")
    for uid in DEMO_USERS:
        client(uid).post("/follow", json={"user_id": PID})
    print("  " + ", ".join(DEMO_USERS))

    step(f"Fast-forwarding the replay {STAGE_FROM} -> {STAGE_TO} (600x)")
    c.post("/stream/start", json={"speed": 600, "start_at": STAGE_FROM})
    target = minutes(STAGE_TO)
    while True:
        st = c.get("/stream/status").json()
        if st["replay_clock"] and minutes(st["replay_clock"]) >= target - 1:
            break
        time.sleep(1)
    c.post("/stream/pause")
    c.post("/stream/speed", json={"speed": 60})
    st = c.get("/stream/status").json()
    print(f"  paused at {st['replay_clock']}, speed {st['speed']}x")
    pending = [p for p in c.get("/predictions?status=pending").json()["predictions"] if p["kind"] == "meal"]
    for p in pending[:3]:
        print(f"  pending: {p['about']} · I predicted {p['predicted_peak_mg_dl']:.0f} · grades after {p['window_end'][11:16]}")

    step("Warming up chat")
    t1 = time.time()
    with c.stream("POST", "/chat", json={"message": "hi gummi!"}) as r:
        for _ in r.iter_lines():
            pass
    print(f"  {time.time() - t1:.1f}s")

    step("Ready. Open on the projector laptop:")
    print(f"  system map   {APP}/map\n  fleet view   {APP}/fleet/view\n"
          f"  notebook     {WORKSPACE}/#workspace/Workspace/Shared/gummi\n"
          f"  MLflow       {WORKSPACE}/ml/experiments/3505481683626519\n"
          f"  Gummi Insights {WORKSPACE}/ml/endpoints/mas-becc8b0e-endpoint")
    print("\n  Ask Nikhil to start gummi_stream in continuous mode now. Keep MLflow monitors paused.")
    print("  On stage: `.venv/bin/python scripts/demo_stage.py go` (or Resume in the phone's demo controls).")


def go() -> float:
    c = client()
    seen = {x["card_id"] for x in client("u_mahil").get("/feed").json()["cards"] if x["type"] == "meal_story"}
    c.post("/stream/resume")
    t0 = time.time()
    print("▸ Resumed at 60x. Waiting for the Meal Story...", flush=True)
    while time.time() - t0 < 90:
        cards = client("u_mahil").get("/feed").json()["cards"]
        story = next((x for x in cards if x["type"] == "meal_story" and x["card_id"] not in seen), None)
        if story:
            print(f"  landed after {time.time() - t0:.0f}s: [{story['generated_by']}] {story['title']}: {story['body']}")
            return time.time() - t0
        time.sleep(1)
    print("  no meal story within 90 s")
    return -1


def verify() -> None:
    stage(False)
    took = go()
    c = client("u_mahil")
    time.sleep(8)                      # the Meal Story agent upgrades the template card
    cards = c.get("/feed").json()["cards"]
    s = c.get("/state").json()
    checks = {
        "meal story landed": took > 0,
        "agent-written card present": any(x["generated_by"] == "agent" for x in cards),
        "grade with both baselines": any(g["cgm_only_mae_mg_dl"] is not None for g in c.get("/grades").json()["grades"]),
        "food log has study meals": any(e["origin"] == "study_log" for e in c.get("/foodlog").json()["entries"]),
        "chart: confirmed + estimate + forecast": bool(s["confirmed"] and s["estimate"] and s["forecast"]),
        "Dexcom connected": s["dexcom"]["connected"],
        "map active": bool(client().get("/map/state").json()["feed"]),
    }
    print("\n▸ Verify")
    for k, v in checks.items():
        print(f"  {'✓' if v else '✗'} {k}")
    print("ALL GOOD" if all(checks.values()) else "SOME CHECKS FAILED")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stage"
    {"stage": lambda: stage("--redeploy" in sys.argv), "go": go, "verify": verify}[cmd]()
