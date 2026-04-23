# ERPNext16 image inputs

这个目录只保留 **AIO 构建输入**。

## 当前职责

- `apps.json` / `apps.json.example`：官方 app 清单输入
- `build.sh` / `Containerfile`：本地调试与 AIO 构建辅助
- 构建前通过 `../scripts/fetch-private-customizations.sh` 拉取私有定制仓库中的 `erpnext16/custom-apps/`

## 私有定制仓库

业务 custom app 已迁移到私有仓库：

- `ashanzzz/erpnext-private-customizations`

本仓库不再保存 `ashan_cn_procurement` 源码主副本。

## 同步策略

- GitHub Actions AIO workflow 会在每月定时构建时先拉取私有仓库
- 私有仓库本身 **不负责** 反向触发 `ashanzzz/docker` 的 build
- GitHub Actions secret 名称：`PRIVATE_CUSTOM_REPO_PAT`
- 本地手动构建时继续使用环境变量：`PRIVATE_CUSTOM_REPO_TOKEN`

## 本地构建

```bash
cd erpnext16/image
PRIVATE_CUSTOM_REPO_TOKEN=你的GitHubToken bash build.sh
```

`build.sh` 会先同步私有定制仓库，再执行 Docker build。
