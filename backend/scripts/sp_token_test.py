"""D-06 spike, step 2: the iPhone's way in. Client credentials -> OAuth token -> App. Never prints secrets or tokens."""
import time
from pathlib import Path

import httpx

WORKSPACE = "https://dbc-0f92eb43-532a.cloud.databricks.com"
APP = "https://gummi-7474657192035402.aws.databricksapps.com/api/v1"
env = dict(l.split("=", 1) for l in (Path(__file__).parents[1] / "secrets/iphone_sp.env").read_text().split("\n") if "=" in l)
cid, secret = env["GUMMI_SP_CLIENT_ID"].strip(), env["GUMMI_SP_CLIENT_SECRET"].strip()
print("secret present:", bool(secret), "length", len(secret))

t0 = time.time()
r = httpx.post(f"{WORKSPACE}/oidc/v1/token", auth=(cid, secret),
               data={"grant_type": "client_credentials", "scope": "all-apis"}, timeout=20)
print("token endpoint:", r.status_code, f"{time.time()-t0:.2f}s", {k: v for k, v in r.json().items() if k != "access_token"})
tok = r.json()["access_token"]
h = {"Authorization": f"Bearer {tok}", "X-User-Id": "u_mahil"}

r = httpx.get(f"{APP}/health", headers=h, timeout=20)
print("health:", r.status_code, r.text[:120])
t0 = time.time()
with httpx.stream("GET", f"{APP}/live", params={"ping_seconds": 2}, headers=h, timeout=30) as s:
    print("live:", s.status_code)
    n = 0
    for line in s.iter_lines():
        if line.startswith("event:"):
            n += 1
            print(f"  +{time.time()-t0:5.2f}s {line}")
        if n >= 3:
            break
