"""Dexcom API v3 sandbox: OAuth 2.0 authorization code flow, token refresh, dataRange and EGVs (D-17, D-18, D-30).

Status-only by default (D-30): Gummi shows the connection, the data range and the last sync. Sandbox glucose never
feeds coaching or hot state. Tokens stay in the backend (CONTRACT section 2): in memory, plus an encrypted copy in the
App's Unity Catalog volume so a redeploy keeps the connection. The key derives from the Dexcom client secret, which
only the App can read from the gummi secret scope. Disconnect deletes both.
"""
import hashlib
import hmac
import io
import json
import logging
import os
import secrets
import threading
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx

from .. import activity, config

log = logging.getLogger("gummi.dexcom")
BASE = os.environ.get("GUMMI_DEXCOM_BASE", "https://sandbox-api.dexcom.com")
CLIENT_ID = os.environ.get("GUMMI_DEXCOM_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("GUMMI_DEXCOM_CLIENT_SECRET", "")
REDIRECT_URI = os.environ.get("GUMMI_DEXCOM_REDIRECT_URI",
                              "https://gummi-7474657192035402.aws.databricksapps.com/api/v1/dexcom/callback")
_STATE_KEY = secrets.token_bytes(32)
_lock = threading.Lock()
_tokens: dict[str, dict] = {}        # user_id -> {access_token, refresh_token, expires_at}
_status: dict[str, dict] = {}        # user_id -> DexcomStatus extras


TOKENS_PATH = f"/Volumes/{config.CATALOG}/gummi_data/landing/agent_memory/dexcom_tokens.bin"


def _keystream(n: int, nonce: bytes) -> bytes:
    key = hashlib.sha256(b"gummi-dexcom-tokens:" + CLIENT_SECRET.encode()).digest()
    out = b""
    counter = 0
    while len(out) < n:
        out += hmac.new(key, nonce + counter.to_bytes(8, "big"), hashlib.sha256).digest()
        counter += 1
    return out[:n]


def _persist() -> None:
    try:
        from databricks.sdk import WorkspaceClient
        with _lock:
            raw = json.dumps(_tokens).encode()
        nonce = secrets.token_bytes(16)
        body = nonce + bytes(a ^ b for a, b in zip(raw, _keystream(len(raw), nonce)))
        mac = hmac.new(hashlib.sha256(CLIENT_SECRET.encode()).digest(), body, hashlib.sha256).digest()
        WorkspaceClient().files.upload(TOKENS_PATH, io.BytesIO(mac + body), overwrite=True)
    except Exception as e:  # noqa: BLE001
        log.warning("dexcom tokens not persisted: %s", str(e)[:160])


def restore() -> None:
    """At startup: reload connections saved before a redeploy, then sync them."""
    if not configured():
        return
    try:
        from databricks.sdk import WorkspaceClient
        blob = WorkspaceClient().files.download(TOKENS_PATH).contents.read()
        mac, body = blob[:32], blob[32:]
        if not hmac.compare_digest(mac, hmac.new(hashlib.sha256(CLIENT_SECRET.encode()).digest(), body, hashlib.sha256).digest()):
            log.warning("dexcom token file failed its integrity check; ignoring it")
            return
        nonce, enc = body[:16], body[16:]
        data = json.loads(bytes(a ^ b for a, b in zip(enc, _keystream(len(enc), nonce))))
        with _lock:
            _tokens.update(data)
        log.info("restored Dexcom connections for %s", sorted(data))
        for uid in list(data):
            sync_user(uid)
    except Exception as e:  # noqa: BLE001 (no file yet is normal)
        log.info("no saved Dexcom connections (%s)", str(e)[:80])


def configured() -> bool:
    return bool(CLIENT_ID and CLIENT_SECRET)


def _sign(user_id: str) -> str:
    nonce = secrets.token_hex(8)
    mac = hmac.new(_STATE_KEY, f"{user_id}.{nonce}".encode(), hashlib.sha256).hexdigest()[:24]
    return f"{user_id}.{nonce}.{mac}"


def verify_state(state: str) -> str | None:
    try:
        user_id, nonce, mac = state.split(".")
    except (AttributeError, ValueError):
        return None
    good = hmac.new(_STATE_KEY, f"{user_id}.{nonce}".encode(), hashlib.sha256).hexdigest()[:24]
    return user_id if hmac.compare_digest(mac, good) else None


def login_url(user_id: str) -> str:
    q = {"client_id": CLIENT_ID, "redirect_uri": REDIRECT_URI, "response_type": "code", "scope": "offline_access",
         "state": _sign(user_id)}
    return f"{BASE}/v3/oauth2/login?{urlencode(q)}"


def _token(form: dict) -> dict:
    r = httpx.post(f"{BASE}/v3/oauth2/token", data={**form, "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET},
                   headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=20)
    r.raise_for_status()
    t = r.json()
    return {"access_token": t["access_token"], "refresh_token": t.get("refresh_token"),
            "expires_at": time.time() + float(t.get("expires_in", 7200)) - 120}


def exchange_code(user_id: str, code: str) -> None:
    tok = _token({"grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT_URI})
    with _lock:
        _tokens[user_id] = tok
    _persist()
    activity.hit("source.dexcom", detail=f"{user_id} connected the Dexcom sandbox", log=True)
    sync_user(user_id)


def _access(user_id: str) -> str | None:
    with _lock:
        tok = _tokens.get(user_id)
    if not tok:
        return None
    if time.time() >= tok["expires_at"] and tok.get("refresh_token"):
        new = _token({"grant_type": "refresh_token", "refresh_token": tok["refresh_token"]})
        new["refresh_token"] = new.get("refresh_token") or tok["refresh_token"]
        with _lock:
            _tokens[user_id] = tok = new
        _persist()
    return tok["access_token"]


def _get(user_id: str, path: str, params: dict | None = None) -> dict:
    r = httpx.get(f"{BASE}{path}", params=params or {}, headers={"Authorization": f"Bearer {_access(user_id)}"}, timeout=20)
    r.raise_for_status()
    return r.json()


def _end_time(dr: dict) -> str | None:
    egvs = dr.get("egvs") or {}
    end = egvs.get("end") or {}
    return end.get("systemTime")


def sync_user(user_id: str) -> dict:
    """Status-only sync: data range plus the newest EGV, so the phone shows connected, data_through and last_sync."""
    st = {"last_sync": None, "data_through": None, "last_error": None, "latest_egv": None, "range_start": None}
    try:
        dr = _get(user_id, "/v3/users/self/dataRange")
        end = _end_time(dr)
        st["range_start"] = ((dr.get("egvs") or {}).get("start") or {}).get("systemTime")
        if end:
            end_dt = datetime.fromisoformat(end.replace("Z", "+00:00")).replace(tzinfo=None)
            fmt = "%Y-%m-%dT%H:%M:%S"
            eg = _get(user_id, "/v3/users/self/egvs", {"startDate": (end_dt - timedelta(hours=3)).strftime(fmt),
                                                       "endDate": (end_dt + timedelta(minutes=1)).strftime(fmt)})
            recs = [x for x in eg.get("records", []) if x.get("value") is not None]
            if recs:
                last = max(recs, key=lambda x: x["systemTime"])
                st["latest_egv"] = {"value": last["value"], "trend": last.get("trend"), "systemTime": last["systemTime"]}
            st["data_through"] = (end if end.endswith("Z") or "+" in end else end + "Z")
        st["last_sync"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        activity.hit("source.dexcom", detail=f"{user_id}: data through {st['data_through']}")
    except Exception as e:  # noqa: BLE001
        st["last_error"] = f"{type(e).__name__}: {str(e)[:160]}"
        log.warning("dexcom sync failed for %s: %s", user_id, st["last_error"])
    with _lock:
        _status[user_id] = st
    return st


def disconnect(user_id: str) -> None:
    with _lock:
        _tokens.pop(user_id, None)
        _status.pop(user_id, None)
    _persist()


def status(user_id: str) -> dict:
    with _lock:
        connected = user_id in _tokens
        st = dict(_status.get(user_id) or {})
    return {"connected": connected, "environment": "sandbox" if "sandbox" in BASE else "production",
            "data_through": st.get("data_through") if connected else None, "delay_minutes": config.DELAY_MINUTES,
            "last_sync": st.get("last_sync") if connected else None, "last_error": st.get("last_error") if connected else None,
            "source": "dexcom_api" if connected else "replay", "ingest_mode": "status_only"}


def details(user_id: str) -> dict:
    with _lock:
        return dict(_status.get(user_id) or {})


def connected_users() -> list[str]:
    with _lock:
        return list(_tokens)


async def run() -> None:
    """Every 5 minutes: refresh tokens as needed and update status for every connected user (D-30)."""
    import asyncio
    await asyncio.to_thread(restore)
    while True:
        await asyncio.sleep(300)
        for uid in connected_users():
            await asyncio.to_thread(sync_user, uid)
