#!/usr/bin/env python3
"""requests skeleton for web challenges: one session, optional proxy, quick helpers.

    python3 web_session.py http://target:8080
    BURP=1 python3 web_session.py http://target:8080      # route through Burp on 127.0.0.1:8080

Fill in solve(); everything else is plumbing that is easy to get wrong under time pressure.
"""
from __future__ import annotations

import os
import re
import sys

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
FLAG = re.compile(rb"[A-Za-z0-9_]{2,16}\{[^}\s]{1,200}\}")   # TODO tighten to the event's flag format


def new_session() -> requests.Session:
    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0 (ctf)"
    s.verify = False
    if os.environ.get("BURP"):
        s.proxies = {"http": "http://127.0.0.1:8080", "https": "http://127.0.0.1:8080"}
    return s


def find_flags(body: bytes) -> list[str]:
    return sorted({m.decode(errors="replace") for m in FLAG.findall(body)})


def show(r: requests.Response) -> requests.Response:
    print(f"{r.request.method} {r.url} -> {r.status_code} ({len(r.content)} bytes)")
    for flag in find_flags(r.content):
        print("  FLAG?", flag)
    return r


def solve(base: str, s: requests.Session) -> None:
    show(s.get(base + "/"))
    # TODO e.g. log in, then probe:
    # show(s.post(base + "/login", data={"username": "admin", "password": "' OR 1=1-- -"}))
    # show(s.get(base + "/api/user", params={"id": "1 UNION SELECT 1,2,3-- -"}))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    solve(sys.argv[1].rstrip("/"), new_session())
