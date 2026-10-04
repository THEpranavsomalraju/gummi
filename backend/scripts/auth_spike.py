"""D-06 spike: call the deployed App like the iPhone would (bearer token, no browser cookies). Never prints tokens."""
import sys, time
import httpx
from databricks.sdk import WorkspaceClient

APP = "https://gummi-7474657192035402.aws.databricksapps.com/api/v1"
w = WorkspaceClient(profile="gummi")
headers = w.config.authenticate()          # {"Authorization": "Bearer ..."} from the CLI's user OAuth token
headers["X-User-Id"] = "u_pranav"

r = httpx.get(f"{APP}/health", headers=headers, timeout=20)
print("health:", r.status_code, r.headers.get("x-gummi-mode"), r.text[:200])
r = httpx.get(f"{APP}/health", timeout=20, follow_redirects=False)
print("no token:", r.status_code, r.headers.get("location", "")[:80])

t0 = time.time()
with httpx.stream("GET", f"{APP}/live", params={"ping_seconds": 2}, headers=headers, timeout=30) as s:
    print("live:", s.status_code, s.headers.get("content-type"))
    n = 0
    for line in s.iter_lines():
        if line.startswith("event:") or line.startswith(":"):
            print(f"  +{time.time()-t0:5.2f}s {line}")
            n += line.startswith("event:")
        if n >= 4:
            break
