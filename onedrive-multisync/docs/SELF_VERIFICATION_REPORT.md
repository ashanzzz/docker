# onedrive-multisync 自动化集成测试与自检报告 (Self-Verification Report)

## 一、 测试覆盖项
1. **FR-1 单卷多账号自动绑定**：验证 `zeros` 与 `ashanzzz1213` 自动绑定至 `/data/OneDrive-zeros` 与 `/data/OneDrive-ashanzzz1213`。
2. **FR-2 热重载 (`POST /api/v1/reload`)**：验证运行期新增 `corp_edu` 目录秒级拉起独立同步 Worker。
3. **FR-4 状态机与指数退避熔断**：验证模拟 `HTTP 503 Service Unavailable` 时进入 `DEGRADED_RETRYING`，连续失败超过 10 次后精准转入 `NETWORK_DOWN` 并触发熔断告警。
4. **FR-5 无头 OAuth2 闭环**：验证模拟 `401 Unauthorized (invalid_grant)` 时自动进入 `AUTH_REQUIRED`、推送单次防抖 Telegram 告警卡片、通过 `GET /api/v1/accounts/ashanzzz1213/auth-url` 返回登录链接、并通过 `POST /api/v1/accounts/ashanzzz1213/auth-callback` 原子写入 `.response_url` 恢复 `SYNCING`。
5. **FR-6 全部 5 个 REST API 契约核验**：验证 `/health`、`/api/v1/accounts`、`/auth-url`、`/auth-callback`、`/reload` 响应码与 JSON 字段。
6. **NFR 优雅停机 (`SIGTERM`)**：验证守护进程关闭时向所有子进程转发 `SIGTERM` 并完成安全落盘标记 `.graceful_sigterm`。

## 二、 实测执行日志
```text
test_full_lifecycle_and_api_contracts (test_gateway.TestOneDriveMultiSyncGateway.test_full_lifecycle_and_api_contracts) ... 2026-11-14 14:09:16,391 [INFO] [onedrive-multisync] Started account worker: ashanzzz1213 -> /tmp/tmpglksqqg9/data/OneDrive-ashanzzz1213
2026-11-14 14:09:16,391 [INFO] [onedrive-multisync] Started account worker: zeros -> /tmp/tmpglksqqg9/data/OneDrive-zeros
2026-11-14 14:09:16,391 [INFO] [onedrive-multisync] [ashanzzz1213] No refresh_token found; starting in AUTH_REQUIRED flow
2026-11-14 14:09:16,397 [INFO] [asyncio] <Server sockets=(<asyncio.TransportSocket fd=8, family=2, type=1, proto=6, laddr=('127.0.0.1', 45389)>,)> is serving
2026-11-14 14:09:16,397 [INFO] [onedrive-multisync] Management REST API listening on http://127.0.0.1:45389
2026-11-14 14:09:16,397 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=603 running stdout=<_UnixReadPipeTransport fd=6 polling>>
2026-11-14 14:09:16,397 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=605 running stdout=<_UnixReadPipeTransport fd=7 polling>>
2026-11-14 14:09:16,409 [INFO] [onedrive-multisync] Telegram credentials not configured; recorded alert locally for ashanzzz1213 (AUTH_REQUIRED)
2026-11-14 14:09:16,918 [INFO] [onedrive-multisync] Started account worker: corp_edu -> /tmp/tmpglksqqg9/data/OneDrive-corp_edu
2026-11-14 14:09:16,920 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=608 running stdout=<_UnixReadPipeTransport fd=11 polling>>
2026-11-14 14:09:16,938 [INFO] [asyncio] <_UnixReadPipeTransport fd=11 polling> was closed by peer
2026-11-14 14:09:16,938 [INFO] [asyncio] <_UnixSubprocessTransport pid=608 running stdout=<_UnixReadPipeTransport closed fd=11 closed>> exited with return code 1
2026-11-14 14:09:16,955 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=610 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:16,972 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:16,972 [INFO] [asyncio] <_UnixSubprocessTransport pid=610 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,004 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=612 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,021 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,021 [INFO] [asyncio] <_UnixSubprocessTransport pid=612 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,083 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=614 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,100 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,100 [INFO] [asyncio] <_UnixSubprocessTransport pid=614 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,252 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=616 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,270 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,270 [INFO] [asyncio] <_UnixSubprocessTransport pid=616 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,422 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=618 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,440 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,441 [INFO] [asyncio] <_UnixSubprocessTransport pid=618 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,592 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=620 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,610 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,610 [INFO] [asyncio] <_UnixSubprocessTransport pid=620 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,762 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=622 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,781 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,781 [INFO] [asyncio] <_UnixSubprocessTransport pid=622 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:17,933 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=624 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:17,952 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:17,952 [INFO] [asyncio] <_UnixSubprocessTransport pid=624 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:18,105 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=626 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:18,123 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:18,123 [INFO] [asyncio] <_UnixSubprocessTransport pid=626 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:18,275 [INFO] [asyncio] execute program '/usr/bin/python3': <_UnixSubprocessTransport pid=628 running stdout=<_UnixReadPipeTransport fd=9 polling>>
2026-11-14 14:09:18,293 [INFO] [asyncio] <_UnixReadPipeTransport fd=9 polling> was closed by peer
2026-11-14 14:09:18,293 [INFO] [asyncio] <_UnixSubprocessTransport pid=628 running stdout=<_UnixReadPipeTransport closed fd=9 closed>> exited with return code 1
2026-11-14 14:09:18,293 [INFO] [onedrive-multisync] Telegram credentials not configured; recorded alert locally for corp_edu (NETWORK_DOWN)
2026-11-14 14:09:18,338 [INFO] [onedrive-multisync] [ashanzzz1213] Sending SIGTERM to onedrive pid=603
2026-11-14 14:09:18,338 [INFO] [onedrive-multisync] [zeros] Sending SIGTERM to onedrive pid=605
2026-11-14 14:09:18,342 [INFO] [asyncio] <_UnixReadPipeTransport fd=7 polling> was closed by peer
2026-11-14 14:09:18,344 [INFO] [asyncio] <_UnixReadPipeTransport fd=6 polling> was closed by peer
2026-11-14 14:09:18,344 [INFO] [asyncio] <_UnixSubprocessTransport pid=605 running stdout=<_UnixReadPipeTransport closed fd=7 closed>> exited with return code 0
2026-11-14 14:09:18,344 [INFO] [asyncio] <_UnixSubprocessTransport pid=603 running stdout=<_UnixReadPipeTransport closed fd=6 closed>> exited with return code 0
ok

----------------------------------------------------------------------
Ran 1 test in 1.957s

OK
```
