#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"
SITE = os.environ.get("SITE_NAME", "site1.local")
TIMEOUT = 8


def fail(message: str) -> int:
    print(f"[health] {message}", file=sys.stderr)
    return 1


def open_url(url: str, method: str = "GET"):
    request = urllib.request.Request(
        url,
        method=method,
        headers={"Host": SITE, "User-Agent": "erpnext16-healthcheck"},
    )
    return urllib.request.urlopen(request, timeout=TIMEOUT)


def main() -> int:
    try:
        with open_url(f"{BASE}/login") as response:
            html = response.read().decode("utf-8", "replace")
            if response.status != 200:
                return fail(f"/login returned HTTP {response.status}")
    except Exception as exc:
        return fail(f"/login failed: {exc}")

    assets: list[str] = []
    for url in re.findall(
        r'(?:href|src)=["\'](/assets/[^"\']+\.(?:css|js)[^"\']*)["\']',
        html,
    ):
        if url not in assets:
            assets.append(url)

    if len(assets) < 2:
        return fail(f"too few assets in login page: {len(assets)}")

    for url in assets[:6]:
        try:
            with open_url(f"{BASE}{url}", method="HEAD") as response:
                if response.status != 200:
                    return fail(f"asset {url} returned HTTP {response.status}")
        except urllib.error.HTTPError as exc:
            return fail(f"asset {url} returned HTTP {exc.code}")
        except Exception as exc:
            return fail(f"asset {url} failed: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
