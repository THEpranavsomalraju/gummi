"""Smoke test against the deployed App, authenticated exactly like the iPhone (gummi-iphone client credentials).

    .venv/bin/python scripts/smoke.py            # every route
    .venv/bin/python scripts/smoke.py --landing  # plus a 15 s mock replay and a check that the App wrote to landing
Never prints secrets or tokens.
"""
import json
import sys
import time
from pathlib import Path

import httpx

WORKSPACE = "https://dbc-0f92eb43-532a.cloud.databricks.com"
APP = "https://gummi-7474657192035402.aws.databricksapps.com/api/v1"
env = dict(l.split("=", 1) for l in (Path(__file__).parents[1] / "secrets/iphone_sp.env").read_text().split("\n") if "=" in l)
tok = httpx.post(f"{WORKSPACE}/oidc/v1/token", auth=(env["GUMMI_SP_CLIENT_ID"].strip(), env["GUMMI_SP_CLIENT_SECRET"].strip()),
                 data={"grant_type": "client_credentials", "scope": "all-apis"}, timeout=20).json()["access_token"]
c = httpx.Client(base_url=APP, headers={"Authorization": f"Bearer {tok}", "X-User-Id": "u_smoke"}, timeout=30)
fails = 0


def check(method, path, expect=200, **kw):
    global fails
    t0 = time.time()
    r = c.request(method, path, **kw)
    ms = (time.time() - t0) * 1000
    good = r.status_code == expect and r.headers.get("x-gummi-mode") in ("mock", "live")
    fails += not good
    print(f"{'ok ' if good else 'FAIL'} {method:6s} {path:32s} {r.status_code} {ms:6.0f} ms")
    return r


check("GET", "/health")
check("GET", "/state")
check("POST", "/follow", json={"user_id": "p_012"})
check("GET", "/feed")
check("GET", "/predictions?status=pending")
check("GET", "/grades")
m = check("POST", "/meals", json={"items": [{"name": "waffle", "quantity": 2}], "source": "manual"}).json()
check("PATCH", f"/meals/{m['meal_id']}", json={"items": [{"name": "waffle", "quantity": 1}]})
check("GET", "/meals")
check("DELETE", f"/meals/{m['meal_id']}")
check("POST", "/meals/due/d_1/log")
check("POST", "/simulate", json={"items": [{"name": "cookie"}], "eat_at": None})
check("POST", "/vitals", json={"samples": [{"type": "steps", "value": 100, "start": "2026-10-03T12:00:00Z", "end": "2026-10-03T12:05:00Z"}]})
check("POST", "/events", json={"type": "walk_started"})
check("POST", "/events", json={"type": "walk_completed"})
check("GET", "/walks/latest")
check("GET", "/profile")
check("PUT", "/profile", json={"display_name": "Smoke"})
check("GET", "/stream/status")
check("GET", "/fleet")
check("GET", "/fleet/view")
check("GET", "/dexcom/status")
check("GET", "/engine")
check("GET", "/meals/nope", expect=405)

t0 = time.time()
with c.stream("POST", "/chat", json={"message": "can I eat a cookie now?"}) as s:
    first = None
    kinds = []
    for line in s.iter_lines():
        if line.startswith("event:"):
            kinds.append(line[7:])
            if line == "event: token" and first is None:
                first = time.time() - t0
    print(f"ok   chat stream: first token {first:.2f} s, events {sorted(set(kinds))}")

t0 = time.time()
with c.stream("GET", "/live") as s:
    for line in s.iter_lines():
        if line.startswith("event:"):
            print(f"ok   live: first event '{line[7:]}' after {time.time() - t0:.2f} s")
            break

if "--landing" in sys.argv:
    check("POST", "/stream/start", json={"speed": 60, "start_at": "day6T06:00"})
    time.sleep(25)          # first upload includes SDK client setup
    landing = c.get("/engine").json()["landing"]
    check("POST", "/stream/stop")
    print("landing:", json.dumps(landing))
    fails += not landing["files_written"]

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
