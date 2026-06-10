#!/usr/bin/env python3
"""Healthcheck for ERPNext16 AIO.

Checks:
1. /login returns 200
2. The login page references at least a few CSS/JS bundles under /assets/
3. Those bundles are individually reachable

This catches the common failure mode where HTML is served but assets 404.
"""

from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"
TIMEOUT = 8
VERBOSE = "--verbose" in sys.argv


def log(message: str) -> None:
    if VERBOSE:
        print(f"[aio-healthcheck] {message}")


def request(url: str, method: str = "GET") -> tuple[int, str]:
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "hermes-healthcheck"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        body = resp.read().decode("utf-8", "replace")
        return resp.status, body


def fail(message: str, code: int = 1) -> int:
    print(f"[aio-healthcheck] {message}", file=sys.stderr)
    return code


def main() -> int:
    try:
        log(f"requesting {BASE}/login")
        status, html = request(f"{BASE}/login")
    except Exception as exc:  # pragma: no cover - runtime guard
        return fail(f"/login request failed: {exc}")

    if status != 200:
        return fail(f"/login returned HTTP {status}")

    log(f"/login returned HTTP {status}, html_bytes={len(html.encode('utf-8', 'replace'))}")

    asset_urls: list[str] = []
    for url in re.findall(r'(?:href|src)=["\'](/assets/[^"\']+\.(?:css|js)[^"\']*)["\']', html):
        if url not in asset_urls:
            asset_urls.append(url)

    if len(asset_urls) < 3:
        return fail(f"expected at least 3 asset URLs in /login HTML, found {len(asset_urls)}")

    log(f"found {len(asset_urls)} asset urls in login html")
    for url in asset_urls:
        log(f"asset-ref {url}")

    for url in asset_urls:
        try:
            log(f"HEAD {BASE}{url}")
            req = urllib.request.Request(f"{BASE}{url}", method="HEAD", headers={"User-Agent": "hermes-healthcheck"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                if resp.status != 200:
                    return fail(f"asset {url} returned HTTP {resp.status}")
                log(f"asset-ok {url} -> HTTP {resp.status}")
        except urllib.error.HTTPError as exc:
            return fail(f"asset {url} returned HTTP {exc.code}")
        except Exception as exc:  # pragma: no cover - runtime guard
            return fail(f"asset {url} check failed: {exc}")

    log("all login assets reachable")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
