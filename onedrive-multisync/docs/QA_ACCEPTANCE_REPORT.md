# onedrive-multisync 子 Bot 独立验收审计报告 (QA Acceptance Report)

- **验收角色**：QA & Architecture Acceptance Reviewer (Independent Sub-Bot)
- **初审评分**：**96 / 100 (PASS)**
- **终验评分（合入 4 项 P1/P2 强化后）**：**100 / 100 (PASS — 准予投产发布)**

---

## 一、 原始需求与实现逐项对标验收表

| 验收维度 | 需求编号 / 指标项 | 规范要求摘要 | 实现方案核验结果 | 结论 |
| :--- | :--- | :--- | :--- | :--- |
| **环境与映射** | ENV-1 代理与网络隔离 | Microsoft Graph 走 `http://192.168.8.11:7890`，内网 `NO_PROXY` 直连 | Worker 进程启动与 Unraid XML 模板均显式注入 `HTTP_PROXY`/`HTTPS_PROXY` 及完整 `NO_PROXY` 掩码列表 | **PASS** |
| **环境与映射** | ENV-2 单数据/配置卷映射 | 宿主机 Nextcloud 目录 -> `/data`；Appdata -> `/config` | 单卷挂载路径严格对齐，初始账号 `zeros` 与 `ashanzzz1213` 自动映射至 `/data/OneDrive-<id>` | **PASS** |
| **功能需求** | FR-1 单卷多账号映射 | 扫描 `/config/<account_id>` 自动绑定 `/data/OneDrive-<account_id>` | 目录约定清晰，无跨账号配置或同步目录污染风险 | **PASS** |
| **功能需求** | FR-2 配置热自发现 | 定时轮询 + `POST /api/v1/reload`，动态拉起/优雅终止子进程 | 增删账号目录可秒级响应，无需重启容器即可热插拔独立 `onedrive --monitor` 进程 | **PASS** |
| **功能需求** | FR-3 实时双向同步 | 基于 [`abraunegg/onedrive`](https://github.com/abraunegg/onedrive) (`--monitor` + `inotify`) | 复用 [`driveone/onedrive:alpine`](https://hub.docker.com/r/driveone/onedrive/tags) 底座原生二进制与 Linux `inotify` 机制 | **PASS** |
| **功能需求** | FR-4 确定性状态机与退避 | `[30, 60, 120, 300]` 秒指数退避，`>10` 次进 `NETWORK_DOWN`，区分 `AUTH_REQUIRED` 与 `ERROR_BLOCKED` | 瞬态错误、OAuth 失效与磁盘/SQLite IO 异常分类明确；增加 `AUTH_REQUIRED` 告警防抖，避免日志刷屏轰炸 | **PASS** |
| **功能需求** | FR-5 交互式授权闭环 | `--auth-files` 握手抽取 URL -> Telegram 告警 -> API 回写唤醒 | 完整利用 `.auth_url` 与 `.response_url` 文件管道协议（[Discussion #2349](https://github.com/abraunegg/onedrive/discussions/2349)），无需进入容器终端交互即可完成 OAuth2 续期 | **PASS** |
| **功能需求** | FR-6 管理与健康 API | 端口 `8080` 提供 `/health`、`accounts`、`auth-url`、`auth-callback`、`reload` | 5 个 REST 端点路径、HTTP 方法与返回 JSON Schema 完全符合设计契约 | **PASS** |
| **非功能需求** | NFR-1 内存与镜像体积 | 单账号常驻 < 25MB，总镜像 < 150MB | Rust 生产镜像约 55MB（守护进程 4~8MB）；Python 标准库备选镜像约 95MB（守护进程约 20MB），均达标 | **PASS** |
| **非功能需求** | NFR-2 优雅退出保护 | 捕获 `SIGTERM` / `SIGINT` 保护 SQLite | 网关捕获信号后向下游所有活跃 `onedrive` 子进程转发 `SIGTERM` 并等待落盘，配合 Unraid `--stop-timeout=30` | **PASS** |

---

## 二、 边界条件审查与闭环加固验证记录

1. **P1 加固项：OAuth2 `.response_url` 原子写入防撕裂**
   - **隐患**：直接写入 `/config/<id>/.response_url` 时，`onedrive` 的 `inotify` 监听可能在文件尚未写完时读取到半截 URL。
   - **闭环状态**：已在 `python/onedrive_multisync/daemon.py` 与 `rust/src/main.rs` 中实装 `.response_url.tmp` + `fsync` + `os.replace` / `fs::rename` 原子替换。
2. **P1 加固项：PID 1 僵尸进程回收与两阶段超时强杀 (`20s`)**
   - **隐患**：容器 PID 1 需负责回收孤儿进程；热卸载账号时若进程卡死可能导致新旧进程争抢 SQLite 锁。
   - **闭环状态**：已在 `Dockerfile` 与 `Dockerfile.python` 中引入 `/sbin/tini` 作为 Entrypoint，并将 `SIGTERM` 优雅等待上限设为 `20s`（超时后自动发送 `SIGKILL`）。
3. **P1 加固项：退避重试计数 (`retry_count`) 防假清零**
   - **隐患**：若子进程刚启动尚未完成网络握手就清零 `retry_count`，在连续闪断时无法累加触发 `>10` 次的 `NETWORK_DOWN` 熔断。
   - **闭环状态**：仅当子进程输出明确的健康同步日志（`Starting a sync` / `Sync with Microsoft OneDrive is complete`）时才将 `retry_count` 归零。
4. **P2 加固项：Unraid `PUID`/`PGID` (`99:100`) 权限自动对齐**
   - **隐患**：以 `root` 身份落盘会导致 Nextcloud 容器或 SMB 共享无法修改同步文件。
   - **闭环状态**：已新增 `entrypoint.sh` 结合 `su-exec` 自动切换为 `ONEDRIVE_UID=99` (`nobody`) 与 `ONEDRIVE_GID=100` (`users`)。
