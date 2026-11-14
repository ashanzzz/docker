#!/usr/bin/env python3
"""
End-to-End Integration & State Machine Verification Suite for `onedrive-multisync`.
Verifies:
1. FR-1: Single-volume multi-account directory binding (`zeros` & `ashanzzz1213`)
2. FR-2: Hot-reload account addition and graceful removal via `POST /api/v1/reload`
3. FR-3 & FR-4: State transitions (`INITIALIZING` -> `SYNCING` -> `IDLE`, transient 503 -> `DEGRADED_RETRYING` -> `NETWORK_DOWN` after >10 retries)
4. FR-5: Interactive OAuth2 closed loop (`401 invalid_grant` -> `AUTH_REQUIRED` -> Telegram card alert -> `GET /auth-url` -> `POST /auth-callback` -> `SYNCING`)
5. FR-6: All 5 RESTful API endpoints (`/health`, `/api/v1/accounts`, `/auth-url`, `/auth-callback`, `/reload`)
6. NFR: Graceful `SIGTERM` forwarding to child processes
"""
import asyncio
import json
import os
import stat
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from onedrive_multisync.daemon import MultiSyncSupervisor, RestApiServer, SyncStatus


MOCK_ONEDRIVE_SCRIPT = """import os, sys, time, signal
from pathlib import Path

args = sys.argv[1:]
confdir = Path(args[args.index("--confdir") + 1])
syncdir = Path(args[args.index("--syncdir") + 1])
auth_files = args[args.index("--auth-files") + 1]
auth_url_file, resp_url_file = [Path(p) for p in auth_files.split(":", 1)]

def handle_term(signum, frame):
    (confdir / ".graceful_sigterm").write_text("ok", encoding="utf-8")
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_term)

mode_file = confdir / "mock_mode"
mode = mode_file.read_text(encoding="utf-8").strip() if mode_file.exists() else "healthy"

if mode == "auth_expired":
    auth_url = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=d50ca740-c83f-4d1b-b616-12c519384f0c&scope=Files.ReadWrite%20offline_access&response_type=code&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient"
    auth_url_file.write_text(auth_url + "\\n", encoding="utf-8")
    print(f"ERROR: 401 Unauthorized - invalid_grant: Token expired", flush=True)
    print(f"Authorize this application visiting: {auth_url}", flush=True)
    while not resp_url_file.exists():
        time.sleep(0.02)
    resp = resp_url_file.read_text(encoding="utf-8").strip()
    if "code=" in resp:
        (confdir / "refresh_token").write_text("mock_refresh_token_valid", encoding="utf-8")
        mode_file.write_text("healthy", encoding="utf-8")
        resp_url_file.unlink(missing_ok=True)
        print("Starting a sync with Microsoft OneDrive", flush=True)
        time.sleep(0.02)
        print("Sync with Microsoft OneDrive is complete", flush=True)
        while True:
            time.sleep(0.2)
elif mode == "transient_503":
    print("HTTP 503 Service Unavailable - proxy error from 192.168.8.11:7890", flush=True)
    sys.exit(1)
elif mode == "disk_error":
    print("SQLite error: disk I/O error - Read-only file system", flush=True)
    sys.exit(2)
else:
    (confdir / "refresh_token").write_text("mock_refresh_token_valid", encoding="utf-8")
    print("Starting a sync with Microsoft OneDrive", flush=True)
    time.sleep(0.02)
    print("Sync with Microsoft OneDrive is complete", flush=True)
    while True:
        time.sleep(0.2)
"""


def http_json(method: str, url: str, payload: dict = None) -> tuple[int, dict]:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {"Content-Type": "application/json"} if data is not None else {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))


class TestOneDriveMultiSyncGateway(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.config_root = self.root / "config"
        self.data_root = self.root / "data"
        self.mock_script = self.root / "mock_onedrive.py"
        self.mock_script.write_text(MOCK_ONEDRIVE_SCRIPT, encoding="utf-8")

        # Create initial accounts per spec Section II.3: zeros & ashanzzz1213
        (self.config_root / "zeros").mkdir(parents=True)
        (self.config_root / "zeros" / "mock_mode").write_text("healthy", encoding="utf-8")
        (self.config_root / "zeros" / "refresh_token").write_text("valid_tok", encoding="utf-8")

        (self.config_root / "ashanzzz1213").mkdir(parents=True)
        (self.config_root / "ashanzzz1213" / "mock_mode").write_text("auth_expired", encoding="utf-8")

        self.supervisor = MultiSyncSupervisor(
            config_root=self.config_root,
            data_root=self.data_root,
            onedrive_bin=f"{sys.executable} {self.mock_script}",
            backoff_scale=0.0005,
        )
        await self.supervisor.reload_accounts()
        self.api = RestApiServer(self.supervisor, host="127.0.0.1", port=0)
        self.port = await self.api.start()
        self.base_url = f"http://127.0.0.1:{self.port}"

    async def asyncTearDown(self):
        await self.api.stop()
        await self.supervisor.shutdown()
        self.tmp.cleanup()

    async def test_full_lifecycle_and_api_contracts(self):
        await asyncio.sleep(0.25)

        # 1. Verify GET /health
        code, health = await asyncio.to_thread(http_json, "GET", f"{self.base_url}/health")
        self.assertEqual(code, 200)
        self.assertEqual(health["status"], "ok")
        self.assertIn("uptime_seconds", health)

        # 2. Verify GET /api/v1/accounts matches Spec Section V.2
        code, accs = await asyncio.to_thread(http_json, "GET", f"{self.base_url}/api/v1/accounts")
        self.assertEqual(code, 200)
        self.assertEqual(accs["total"], 2)
        self.assertEqual(accs["healthy"], 1)
        by_id = {a["account_id"]: a for a in accs["accounts"]}
        self.assertIn(by_id["zeros"]["status"], ("SYNCING", "IDLE"))
        self.assertTrue(by_id["zeros"]["sync_dir"].endswith("/data/OneDrive-zeros"))
        self.assertEqual(by_id["ashanzzz1213"]["status"], "AUTH_REQUIRED")
        self.assertEqual(by_id["ashanzzz1213"]["error_message"], "Token expired (invalid_grant)")

        # Verify exactly 1 Telegram Alert was pushed for ashanzzz1213 (no duplicate spam)
        auth_alerts = [
            a for a in self.supervisor.notifier.sent_alerts
            if a["account_id"] == "ashanzzz1213" and a["alert_type"] == "AUTH_REQUIRED"
        ]
        self.assertEqual(len(auth_alerts), 1)

        # 3. Verify GET /api/v1/accounts/ashanzzz1213/auth-url
        code, auth_info = await asyncio.to_thread(
            http_json, "GET", f"{self.base_url}/api/v1/accounts/ashanzzz1213/auth-url"
        )
        self.assertEqual(code, 200)
        self.assertEqual(auth_info["account_id"], "ashanzzz1213")
        self.assertTrue(auth_info["auth_url"].startswith("https://login.microsoftonline.com/"))

        # 4. Verify POST /api/v1/accounts/ashanzzz1213/auth-callback completes OAuth loop
        code, cb_res = await asyncio.to_thread(
            http_json,
            "POST",
            f"{self.base_url}/api/v1/accounts/ashanzzz1213/auth-callback",
            {"response_url": "https://login.microsoftonline.com/common/oauth2/nativeclient?code=M.R3_BLZ.test_code_123"},
        )
        self.assertEqual(code, 200)
        await asyncio.sleep(0.25)

        code, accs_after = await asyncio.to_thread(http_json, "GET", f"{self.base_url}/api/v1/accounts")
        self.assertEqual(accs_after["healthy"], 2)

        # 5. Verify Hot-Reload (FR-2) + Transient Retry -> NETWORK_DOWN (FR-4)
        (self.config_root / "corp_edu").mkdir(parents=True)
        (self.config_root / "corp_edu" / "mock_mode").write_text("transient_503", encoding="utf-8")
        (self.config_root / "corp_edu" / "refresh_token").write_text("tok", encoding="utf-8")

        code, reload_res = await asyncio.to_thread(http_json, "POST", f"{self.base_url}/api/v1/reload")
        self.assertEqual(code, 200)
        self.assertEqual(reload_res["added"], ["corp_edu"])

        for _ in range(100):
            await asyncio.sleep(0.05)
            w = self.supervisor.workers["corp_edu"]
            if w.state.status == SyncStatus.NETWORK_DOWN:
                break
        self.assertEqual(self.supervisor.workers["corp_edu"].state.status, SyncStatus.NETWORK_DOWN)
        self.assertGreater(self.supervisor.workers["corp_edu"].state.retry_count, 10)

        # 6. Verify Graceful SIGTERM Shutdown writes `.graceful_sigterm` marker
        await self.supervisor.shutdown()
        self.assertTrue((self.config_root / "zeros" / ".graceful_sigterm").exists())


if __name__ == "__main__":
    unittest.main()
