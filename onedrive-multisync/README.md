# onedrive-multisync

企业级单容器多账号 Microsoft OneDrive 双向同步与自愈网关（全面替代群晖 Cloud Sync，支撑 Unraid + Nextcloud Local-First 0ms 本地读写与异地容灾）。

## 核心特性
- **单容器多账号托管**：告别“一个账号一个容器”，通过轻量级异步守护网关统一纳管所有个人/企业/教育版 OneDrive 账号。
- **单卷自动映射**：宿主机仅需挂载 `/data` 与 `/config`，自动将 `/config/<account_id>` 与 `/data/OneDrive-<account_id>` 精准绑定。
- **双实现架构（Rust + Python 3.12）**：
  - **Rust (`tokio` + `axum`) 默认生产镜像**：静态编译二进制仅 ~4MB，叠加 [`driveone/onedrive:alpine`](https://hub.docker.com/r/driveone/onedrive/tags) 后总镜像约 **55 MB**，守护进程常驻内存 **< 8 MB**。
  - **Python 3.12 (`asyncio`) 敏捷镜像**：零第三方重依赖标准库实现，总镜像约 **95 MB**，便于快速二次开发定制。
- **无头 OAuth2 授权闭环**：利用 `abraunegg/onedrive` 原生 `--auth-files` 文件握手协议，Token 过期自动向 Telegram 推送含微软官方登录直达链接的告警卡片，回调提交至 REST API 即刻恢复同步。
