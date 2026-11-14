#!/usr/bin/env python3
"""
onedrive-multisync: Enterprise Single-Container Multi-Account Bidirectional Sync & Self-Healing Gateway
Supports:
- FR-1: Single volume multi-account mapping (/config/<account_id> <-> /data/OneDrive-<account_id>)
- FR-2: Hot-reload discovery (periodic scan + POST /api/v1/reload)
- FR-3: Real-time bidirectional sync supervision (abraunegg/onedrive --monitor)
- FR-4: Deterministic state machine & exponential backoff (30s -> 60s -> 120s -> 300s, >10 -> NETWORK_DOWN)
- FR-5: Headless OAuth2 closed-loop via `--auth-files` + Telegram Bot card push
- FR-6: HTTP RESTful Management API on port 8080 (/health, /api/v1/accounts, /auth-url, /auth-callback, /reload)
- NFR: Graceful SIGTERM/SIGINT forwarding to protect SQLite WAL/hash integrity
"""
from __future__ import annotations

import asyncio
import datetime as dt
import json
import logging
import os
import re
import shlex
import signal
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
)
logger = logging.getLogger("onedrive-multisync")


class SyncStatus(str, Enum):
    INITIALIZING = "INITIALIZING"
    SYNCING = "SYNCING"
    IDLE = "IDLE"
    DEGRADED_RETRYING = "DEGRADED_RETRYING"
    NETWORK_DOWN = "NETWORK_DOWN"
    AUTH_REQUIRED = "AUTH_REQUIRED"
    ERROR_BLOCKED = "ERROR_BLOCKED"


BACKOFF_SCHEDULE = [30, 60, 120, 300]
MAX_TRANSIENT_RETRIES = 10

AUTH_ERROR_PATTERNS = re.compile(
    r"(401\s+Unauthorized|invalid_grant|AADSTS|token\s+expired|authori[sz]e\s+this\s+application|Enter\s+the\s+response\s+uri)",
    re.IGNORECASE,
)
TRANSIENT_NET_PATTERNS = re.compile(
    r"(50[0234]\s+|429\s+Too\s+Many\s+Requests|Curle_Couldnt_Connect|Could\s+not\s+resolve\s+host|Connection\s+timed\s+out|proxy\s+error|network\s+unreachable|socket\s+timeout)",
    re.IGNORECASE,
)
DISK_IO_PATTERNS = re.compile(
    r"(No\s+space\s+left\s+on\s+device|Read-only\s+file\s+system|Permission\s+denied|SQLite\s+error:\s+disk\s+I/O\s+error)",
    re.IGNORECASE,
)
SYNC_COMPLETE_PATTERNS = re.compile(
    r"(Sync\s+with\s+Microsoft\s+OneDrive\s+is\s+complete|Monitored\s+directory\s+idle)",
    re.IGNORECASE,
)
SYNC_ACTIVE_PATTERNS = re.compile(
    r"(Uploading|Downloading|Deleting|Processing\s+items|Starting\s+a\s+sync|Initializing\s+monitor)",
    re.IGNORECASE,
)


@dataclass
class AccountState:
    account_id: str
    config_dir: Path
    sync_dir: Path
    status: SyncStatus = SyncStatus.INITIALIZING
    last_sync_time: Optional[str] = None
    retry_count: int = 0
    error_message: Optional[str] = None
    auth_url: Optional[str] = None

    @property
    def auth_url_file(self) -> Path:
        return self.config_dir / ".auth_url"

    @property
    def response_url_file(self) -> Path:
        return self.config_dir / ".response_url"

    @property
    def refresh_token_file(self) -> Path:
        return self.config_dir / "refresh_token"

    @property
    def monitor_status_file(self) -> Path:
        return self.config_dir / "monitor-status.json"

    def to_api_dict(self) -> dict:
        return {
            "account_id": self.account_id,
            "sync_dir": str(self.sync_dir),
            "status": self.status.value,
            "last_sync_time": self.last_sync_time,
            "retry_count": self.retry_count,
            "error_message": self.error_message,
        }


class TelegramNotifier:
    """Sends lightweight alert cards to Telegram Bot (via proxy if configured)."""

    def __init__(
        self,
        bot_token: Optional[str] = None,
        chat_id: Optional[str] = None,
        proxy_url: Optional[str] = None,
        gateway_base_url: str = "http://192.168.8.11:8080",
    ):
        self.bot_token = bot_token or os.environ.get("TG_BOT_TOKEN", "")
        self.chat_id = chat_id or os.environ.get("TG_CHAT_ID", "")
        self.proxy_url = proxy_url or os.environ.get("HTTPS_PROXY", "")
        self.gateway_base_url = gateway_base_url
        self.sent_alerts: List[dict] = []

    async def send_auth_alert(self, account_id: str, auth_url: str, reason: str) -> bool:
        card_text = (
            f"🚨 *[OneDrive-MultiSync 授权失效告警]*\n"
            f"• *账号 ID*: `{account_id}`\n"
            f"• *当前状态*: `AUTH_REQUIRED`\n"
            f"• *原因*: `{reason}`\n\n"
            f"👉 [点击直达微软官方登录授权]({auth_url})\n\n"
            f"授权完成后，将浏览器地址栏的 `nativeclient?code=...` 回调链接提交至：\n"
            f"`POST {self.gateway_base_url}/api/v1/accounts/{account_id}/auth-callback`"
        )
        return await self._send_message(account_id, "AUTH_REQUIRED", card_text, auth_url)

    async def send_network_down_alert(self, account_id: str, retry_count: int, last_error: str) -> bool:
        card_text = (
            f"⚠️ *[OneDrive-MultiSync 网络熔断告警]*\n"
            f"• *账号 ID*: `{account_id}`\n"
            f"• *当前状态*: `NETWORK_DOWN` (连续重试 {retry_count} 次失败)\n"
            f"• *最近错误*: `{last_error}`\n"
            f"• *本地读写*: 不受影响 (Local-First 正常落盘)"
        )
        return await self._send_message(account_id, "NETWORK_DOWN", card_text, None)

    async def _send_message(
        self, account_id: str, alert_type: str, text: str, auth_url: Optional[str]
    ) -> bool:
        record = {
            "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "account_id": account_id,
            "alert_type": alert_type,
            "auth_url": auth_url,
            "text": text,
        }
        self.sent_alerts.append(record)
        if not self.bot_token or not self.chat_id:
            logger.info("Telegram credentials not configured; recorded alert locally for %s (%s)", account_id, alert_type)
            return True

        def _post():
            api_url = f"https://api.telegram.org/bot{self.bot_token}/sendMessage"
            payload = json.dumps({
                "chat_id": self.chat_id,
                "text": text,
                "parse_mode": "Markdown",
                "disable_web_page_preview": True,
            }).encode("utf-8")
            handlers = []
            if self.proxy_url:
                handlers.append(urllib.request.ProxyHandler({"http": self.proxy_url, "https": self.proxy_url}))
            opener = urllib.request.build_opener(*handlers)
            req = urllib.request.Request(api_url, data=payload, headers={"Content-Type": "application/json"})
            with opener.open(req, timeout=10) as resp:
                return resp.status == 200

        try:
            return await asyncio.to_thread(_post)
        except Exception as exc:
            logger.warning("Failed to send Telegram alert for %s: %s", account_id, exc)
            return False


class AccountWorker:
    """Supervises a single `onedrive` OS process and maintains its deterministic state machine."""

    def __init__(
        self,
        state: AccountState,
        onedrive_bin: str,
        proxy_url: Optional[str],
        notifier: TelegramNotifier,
        backoff_scale: float = 1.0,
    ):
        self.state = state
        self.onedrive_bin = onedrive_bin
        self.proxy_url = proxy_url
        self.notifier = notifier
        self.backoff_scale = backoff_scale
        self._proc: Optional[asyncio.subprocess.Process] = None
        self._task: Optional[asyncio.Task] = None
        self._stop_event = asyncio.Event()
        self._wake_event = asyncio.Event()

    def start(self):
        if self._task is None or self._task.done():
            self._stop_event.clear()
            self._task = asyncio.create_task(self._run_loop(), name=f"worker-{self.state.account_id}")

    async def stop(self):
        self._stop_event.set()
        self._wake_event.set()
        await self._terminate_process()
        if self._task and not self._task.done():
            try:
                await asyncio.wait_for(self._task, timeout=5.0)
            except asyncio.TimeoutError:
                self._task.cancel()

    async def _terminate_process(self):
        if self._proc and self._proc.returncode is None:
            logger.info("[%s] Sending SIGTERM to onedrive pid=%s", self.state.account_id, self._proc.pid)
            try:
                self._proc.send_signal(signal.SIGTERM)
                await asyncio.wait_for(self._proc.wait(), timeout=20.0)
            except asyncio.TimeoutError:
                logger.warning("[%s] SIGTERM timed out; sending SIGKILL", self.state.account_id)
                self._proc.kill()
                await self._proc.wait()
            except ProcessLookupError:
                pass

    def _ensure_directories_and_config(self) -> bool:
        try:
            self.state.config_dir.mkdir(parents=True, exist_ok=True)
            self.state.sync_dir.mkdir(parents=True, exist_ok=True)
            cfg_file = self.state.config_dir / "config"
            if not cfg_file.exists():
                lines = [
                    f'sync_dir = "{self.state.sync_dir}"',
                    'monitor_interval = "45"',
                    'skip_dotfiles = "true"',
                    'check_nosync = "true"',
                ]
                if self.proxy_url:
                    lines.append(f'http_proxy = "{self.proxy_url}"')
                cfg_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return True
        except OSError as exc:
            self.state.status = SyncStatus.ERROR_BLOCKED
            self.state.error_message = f"Filesystem permission/IO error: {exc}"
            logger.error("[%s] %s", self.state.account_id, self.state.error_message)
            return False

    async def _enter_auth_required(self, reason: str):
        already_in_auth = self.state.status == SyncStatus.AUTH_REQUIRED
        self.state.status = SyncStatus.AUTH_REQUIRED
        if not already_in_auth or not self.state.error_message:
            self.state.error_message = reason
        self.state.retry_count = 0
        if self.state.response_url_file.exists():
            self.state.response_url_file.unlink(missing_ok=True)

        for _ in range(20):
            if self.state.auth_url_file.exists():
                url_text = self.state.auth_url_file.read_text(encoding="utf-8").strip()
                if url_text.startswith("http"):
                    self.state.auth_url = url_text
                    break
            await asyncio.sleep(0.02)

        if not self.state.auth_url:
            client_id = os.environ.get("ONEDRIVE_CLIENT_ID", "d50ca740-c83f-4d1b-b616-12c519384f0c")
            scope = urllib.parse.quote("Files.ReadWrite Files.ReadWrite.All Sites.ReadWrite.All offline_access")
            redirect = urllib.parse.quote("https://login.microsoftonline.com/common/oauth2/nativeclient", safe="")
            self.state.auth_url = (
                f"https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
                f"?client_id={client_id}&scope={scope}&response_type=code&prompt=login&redirect_uri={redirect}"
            )
            self.state.auth_url_file.write_text(self.state.auth_url + "\n", encoding="utf-8")

        if not already_in_auth:
            await self.notifier.send_auth_alert(self.state.account_id, self.state.auth_url, self.state.error_message)

    async def submit_auth_callback(self, response_url: str) -> bool:
        if "code=" not in response_url:
            raise ValueError("Invalid response_url: missing 'code=' query parameter")
        tmp_file = self.state.config_dir / ".response_url.tmp"
        with open(tmp_file, "w", encoding="utf-8") as f:
            f.write(response_url.strip() + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_file, self.state.response_url_file)
        self.state.error_message = None
        self.state.retry_count = 0
        self._wake_event.set()
        return True

    async def _run_loop(self):
        self.state.status = SyncStatus.INITIALIZING
        if not self._ensure_directories_and_config():
            return

        while not self._stop_event.is_set():
            self._wake_event.clear()

            has_token = self.state.refresh_token_file.exists() and self.state.refresh_token_file.stat().st_size > 0
            has_pending_resp = self.state.response_url_file.exists()

            base_cmd = shlex.split(self.onedrive_bin)
            cmd = base_cmd + [
                "--monitor",
                "--confdir",
                str(self.state.config_dir),
                "--syncdir",
                str(self.state.sync_dir),
                "--auth-files",
                f"{self.state.auth_url_file}:{self.state.response_url_file}",
            ]

            env = os.environ.copy()
            if self.proxy_url:
                env["HTTP_PROXY"] = self.proxy_url
                env["HTTPS_PROXY"] = self.proxy_url
                env["http_proxy"] = self.proxy_url
                env["https_proxy"] = self.proxy_url
            env["NO_PROXY"] = "localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8"

            if not has_token and not has_pending_resp:
                logger.info("[%s] No refresh_token found; starting in AUTH_REQUIRED flow", self.state.account_id)

            try:
                self._proc = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                    env=env,
                )
            except OSError as exc:
                self.state.status = SyncStatus.ERROR_BLOCKED
                self.state.error_message = f"Failed to execute onedrive binary: {exc}"
                return

            if has_token and self.state.retry_count == 0:
                self.state.status = SyncStatus.SYNCING
                self.state.error_message = None

            saw_auth_error = False
            saw_transient_error: Optional[str] = None
            saw_disk_error: Optional[str] = None

            assert self._proc.stdout is not None
            while not self._stop_event.is_set():
                line_bytes = await self._proc.stdout.readline()
                if not line_bytes:
                    break
                line = line_bytes.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                logger.debug("[%s] engine: %s", self.state.account_id, line)

                if "https://login.microsoftonline.com/" in line and "authorize" in line:
                    m = re.search(r"(https://login\.microsoftonline\.com/\S+)", line)
                    if m:
                        self.state.auth_url = m.group(1)
                        self.state.auth_url_file.write_text(self.state.auth_url + "\n", encoding="utf-8")

                if DISK_IO_PATTERNS.search(line):
                    saw_disk_error = line
                    self.state.status = SyncStatus.ERROR_BLOCKED
                    self.state.error_message = line
                elif AUTH_ERROR_PATTERNS.search(line):
                    saw_auth_error = True
                    await self._enter_auth_required(
                        "Token expired (invalid_grant)" if "invalid_grant" in line.lower() else line
                    )
                elif TRANSIENT_NET_PATTERNS.search(line):
                    saw_transient_error = line
                elif SYNC_COMPLETE_PATTERNS.search(line):
                    self.state.status = SyncStatus.IDLE
                    self.state.retry_count = 0
                    self.state.error_message = None
                    self.state.last_sync_time = (
                        dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
                    )
                elif SYNC_ACTIVE_PATTERNS.search(line):
                    self.state.status = SyncStatus.SYNCING
                    self.state.retry_count = 0
                    self.state.error_message = None
                    self.state.last_sync_time = (
                        dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
                    )

            rc = await self._proc.wait()
            if self._stop_event.is_set():
                break

            if saw_disk_error:
                self.state.status = SyncStatus.ERROR_BLOCKED
                break

            if saw_auth_error or (not self.state.refresh_token_file.exists() and rc != 0):
                if self.state.status != SyncStatus.AUTH_REQUIRED:
                    await self._enter_auth_required("Token expired (invalid_grant)")
                await self._wake_event.wait()
                continue

            if saw_transient_error or rc != 0:
                self.state.retry_count += 1
                err_msg = saw_transient_error or f"Process exited with code {rc}"
                self.state.error_message = err_msg

                if self.state.retry_count > MAX_TRANSIENT_RETRIES:
                    self.state.status = SyncStatus.NETWORK_DOWN
                    await self.notifier.send_network_down_alert(
                        self.state.account_id, self.state.retry_count, err_msg
                    )
                    delay = BACKOFF_SCHEDULE[-1] * self.backoff_scale
                else:
                    self.state.status = SyncStatus.DEGRADED_RETRYING
                    idx = min(self.state.retry_count - 1, len(BACKOFF_SCHEDULE) - 1)
                    delay = BACKOFF_SCHEDULE[idx] * self.backoff_scale

                try:
                    await asyncio.wait_for(self._wake_event.wait(), timeout=delay)
                except asyncio.TimeoutError:
                    pass


class MultiSyncSupervisor:
    """Manages all AccountWorkers, hot-reload discovery, and HTTP REST API."""

    def __init__(
        self,
        config_root: Path,
        data_root: Path,
        onedrive_bin: str = "onedrive",
        proxy_url: Optional[str] = None,
        backoff_scale: float = 1.0,
    ):
        self.config_root = config_root
        self.data_root = data_root
        self.onedrive_bin = onedrive_bin
        self.proxy_url = proxy_url if proxy_url is not None else os.environ.get("HTTPS_PROXY", "http://192.168.8.11:7890")
        self.backoff_scale = backoff_scale
        self.start_time = time.monotonic()
        self.notifier = TelegramNotifier(proxy_url=self.proxy_url)
        self.workers: Dict[str, AccountWorker] = {}
        self._lock = asyncio.Lock()

    @property
    def uptime_seconds(self) -> int:
        return int(time.monotonic() - self.start_time)

    async def reload_accounts(self) -> dict:
        """FR-1 & FR-2: Scan /config subdirectories and bind /config/<id> <-> /data/OneDrive-<id>."""
        async with self._lock:
            self.config_root.mkdir(parents=True, exist_ok=True)
            self.data_root.mkdir(parents=True, exist_ok=True)

            discovered_ids = sorted([
                p.name
                for p in self.config_root.iterdir()
                if p.is_dir() and not p.name.startswith(".")
            ])

            added = []
            removed = []

            for existing_id in list(self.workers.keys()):
                if existing_id not in discovered_ids:
                    worker = self.workers.pop(existing_id)
                    await worker.stop()
                    removed.append(existing_id)
                    logger.info("Stopped & removed account worker: %s", existing_id)

            for acc_id in discovered_ids:
                if acc_id not in self.workers:
                    state = AccountState(
                        account_id=acc_id,
                        config_dir=self.config_root / acc_id,
                        sync_dir=self.data_root / f"OneDrive-{acc_id}",
                    )
                    worker = AccountWorker(
                        state=state,
                        onedrive_bin=self.onedrive_bin,
                        proxy_url=self.proxy_url,
                        notifier=self.notifier,
                        backoff_scale=self.backoff_scale,
                    )
                    self.workers[acc_id] = worker
                    worker.start()
                    added.append(acc_id)
                    logger.info("Started account worker: %s -> %s", acc_id, state.sync_dir)

            return {
                "status": "reloaded",
                "added": added,
                "removed": removed,
                "total": len(self.workers),
            }

    async def shutdown(self):
        async with self._lock:
            await asyncio.gather(*(w.stop() for w in self.workers.values()), return_exceptions=True)
            self.workers.clear()

    def get_accounts_payload(self) -> dict:
        accounts_list = [w.state.to_api_dict() for w in self.workers.values()]
        healthy_count = sum(
            1 for w in self.workers.values() if w.state.status in (SyncStatus.SYNCING, SyncStatus.IDLE)
        )
        return {
            "total": len(accounts_list),
            "healthy": healthy_count,
            "accounts": accounts_list,
        }


class RestApiServer:
    """Zero-dependency asyncio HTTP/1.1 JSON server implementing Section V of the specification."""

    def __init__(self, supervisor: MultiSyncSupervisor, host: str = "0.0.0.0", port: int = 8080):
        self.supervisor = supervisor
        self.host = host
        self.port = port
        self._server: Optional[asyncio.AbstractServer] = None

    async def start(self) -> int:
        self._server = await asyncio.start_server(self._handle_client, self.host, self.port)
        socks = self._server.sockets
        if socks:
            self.port = socks[0].getsockname()[1]
        logger.info("Management REST API listening on http://%s:%d", self.host, self.port)
        return self.port

    async def stop(self):
        if self._server:
            self._server.close()
            await self._server.wait_closed()

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            request_line = await asyncio.wait_for(reader.readline(), timeout=5.0)
            if not request_line:
                return
            parts = request_line.decode("utf-8", errors="replace").strip().split(" ")
            if len(parts) < 2:
                return
            method, raw_path = parts[0].upper(), parts[1]
            parsed_path = urllib.parse.urlsplit(raw_path).path

            content_length = 0
            while True:
                hdr_line = await reader.readline()
                if not hdr_line or hdr_line in (b"\r\n", b"\n"):
                    break
                hdr_str = hdr_line.decode("utf-8", errors="replace").strip()
                if hdr_str.lower().startswith("content-length:"):
                    content_length = int(hdr_str.split(":", 1)[1].strip())

            body_bytes = await reader.readexactly(content_length) if content_length > 0 else b""
            status_code, payload = await self._route_request(method, parsed_path, body_bytes)
            await self._write_json(writer, status_code, payload)
        except Exception as exc:
            logger.exception("Error handling HTTP request: %s", exc)
            await self._write_json(writer, 500, {"error": str(exc)})
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _route_request(self, method: str, path: str, body: bytes) -> tuple[int, dict]:
        if method == "GET" and path == "/health":
            return 200, {"status": "ok", "uptime_seconds": self.supervisor.uptime_seconds}

        if method == "GET" and path == "/api/v1/accounts":
            return 200, self.supervisor.get_accounts_payload()

        if method == "POST" and path == "/api/v1/reload":
            res = await self.supervisor.reload_accounts()
            return 200, res

        m_auth_url = re.fullmatch(r"/api/v1/accounts/([^/]+)/auth-url", path)
        if method == "GET" and m_auth_url:
            acc_id = m_auth_url.group(1)
            worker = self.supervisor.workers.get(acc_id)
            if not worker:
                return 404, {"error": f"Account '{acc_id}' not found"}
            if not worker.state.auth_url:
                await worker._enter_auth_required("Manual auth-url requested")
            return 200, {"account_id": acc_id, "auth_url": worker.state.auth_url}

        m_callback = re.fullmatch(r"/api/v1/accounts/([^/]+)/auth-callback", path)
        if method == "POST" and m_callback:
            acc_id = m_callback.group(1)
            worker = self.supervisor.workers.get(acc_id)
            if not worker:
                return 404, {"error": f"Account '{acc_id}' not found"}
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                response_url = data.get("response_url", "")
                await worker.submit_auth_callback(response_url)
                return 200, {
                    "account_id": acc_id,
                    "status": "accepted",
                    "message": "OAuth2 response URL written; worker resuming sync",
                }
            except ValueError as exc:
                return 400, {"error": str(exc)}

        return 404, {"error": f"Endpoint {method} {path} not found"}

    @staticmethod
    async def _write_json(writer: asyncio.StreamWriter, status_code: int, payload: dict):
        reasons = {200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"}
        reason = reasons.get(status_code, "OK")
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = (
            f"HTTP/1.1 {status_code} {reason}\r\n"
            f"Content-Type: application/json; charset=utf-8\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Connection: close\r\n\r\n"
        ).encode("ascii")
        writer.write(headers + body)
        await writer.drain()


async def main_async():
    config_root = Path(os.environ.get("CONFIG_DIR", "/config"))
    data_root = Path(os.environ.get("DATA_DIR", "/data"))
    onedrive_bin = os.environ.get("ONEDRIVE_BIN", "onedrive")
    port = int(os.environ.get("API_PORT", "8080"))
    scan_interval = int(os.environ.get("HOT_RELOAD_INTERVAL", "15"))

    supervisor = MultiSyncSupervisor(
        config_root=config_root,
        data_root=data_root,
        onedrive_bin=onedrive_bin,
    )
    await supervisor.reload_accounts()

    api_server = RestApiServer(supervisor, port=port)
    await api_server.start()

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass

    async def _periodic_scanner():
        while not stop_event.is_set():
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=scan_interval)
            except asyncio.TimeoutError:
                await supervisor.reload_accounts()

    scanner_task = asyncio.create_task(_periodic_scanner())
    await stop_event.wait()
    logger.info("Shutdown signal received; stopping API and flushing onedrive workers...")
    scanner_task.cancel()
    await api_server.stop()
    await supervisor.shutdown()
    logger.info("Graceful shutdown complete.")


if __name__ == "__main__":
    asyncio.run(main_async())