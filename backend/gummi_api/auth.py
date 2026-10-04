"""Caller identity. The Databricks Apps proxy authenticates the bearer token before requests reach us; X-User-Id picks
the Gummi user (CONTRACT section 2). Teammates are u_<name>; requests without the header act as u_demo."""
import re

from fastapi import Header

from .errors import ApiError

USER_RE = re.compile(r"^(u|p)_[a-z0-9_]{1,32}$")


def user_id(x_user_id: str | None = Header(default=None)) -> str:
    uid = (x_user_id or "u_demo").strip().lower()
    if not USER_RE.match(uid):
        raise ApiError(400, "bad_request", "X-User-Id must look like u_<name> or p_<id>")
    return uid
