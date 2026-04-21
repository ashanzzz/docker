# ERPNext16 image inputs

这个目录现在只作为 **AIO 构建依赖** 保留。

它不再代表一个独立部署方案，也不是仓库对外推荐的单独镜像入口。

如果你要实际部署，请直接看：
- `erpnext16/single-aio/README.md`

---

## 这个目录里有什么

- `apps.json`：AIO 构建时实际使用的 app 列表
- `apps.json.example`：可直接复制修改的示例
- `build.sh` / `Containerfile`：保留下来的构建辅助文件，主要供本地调试或后续维护参考
- `../custom-apps/`：随镜像一起打包的本地业务 custom app 源码

---

## 当前版本策略

当前仓库默认策略是：

- `FRAPPE_IMAGE_TAG=version-16`
- `FRAPPE_BRANCH=<优先使用与 ERPNext 相同的精确 v16.x.y tag；找不到时回退到 version-16 分支>`
- ERPNext app 在 workflow 里尽量 pin 到发现到的 `v16.x.y`

这意味着：
- 基础镜像仍然跟 `version-16` 主版本线
- Frappe 源码优先和 ERPNext app 对齐到同一个精确 tag
- 如果官方没有同名 Frappe tag，就回退到 `version-16` 分支继续构建

这样做的目的不是追求绝对锁死，而是保证：
- 能对齐就对齐
- 对不齐时也别把 AIO 构建整条链卡死

---

## 和 AIO workflow 的关系

当前仓库只保留：
- `.github/workflows/erpnext16-single-container-aio.yml`

这条 workflow 会：
- 读取 `erpnext16/image/apps.json`
- 把 ERPNext app pin 到上游精确 tag
- 校验 `frappe/frappe` 是否存在同名 tag
- 最终构建并发布 AIO 镜像

---

## 本地构建（仅供调试）

最简单：

```bash
cd erpnext16/image
bash build.sh
```

默认值：
- `FRAPPE_IMAGE_TAG=version-16`
- `FRAPPE_BRANCH=version-16`
- `FRAPPE_PATH=https://github.com/frappe/frappe`
- `IMAGE=ghcr.io/ashanzzz/erpnext16`
- `TAG=v16-custom`

说明：
- `build.sh` 本地默认值仍然是 `FRAPPE_BRANCH=version-16`，这是为了手动构建时少填参数。
- GitHub Actions 自动发布流程会优先尝试同一个精确 `v16.x.y` tag；如果官方没有同名 Frappe tag，就回退到 `version-16` 分支。
- 如果你想本地复现 CI 的严格策略，构建时请显式传入同一个精确 tag，例如：

```bash
FRAPPE_BRANCH=v16.12.1 TAG=v16.12.1 bash build.sh
```

---

## 常用环境变量

### `FRAPPE_IMAGE_TAG`

控制 `FROM frappe/build:*` 和 `FROM frappe/base:*` 用哪个基础 tag。

### `FRAPPE_BRANCH`

控制 `bench init` 时抓取哪个 Frappe git ref。

### `FRAPPE_PATH`

默认是官方 Frappe 项目地址，一般不用改。

### `APPS_JSON_PATH`

默认是当前目录下的 `apps.json`。

### `IMAGE`

最终镜像名。

### `TAG`

最终镜像 tag。

---

## 如何增加官方 apps

1. 复制一份示例：

```bash
cp apps.json.example apps.json
```

2. 删掉你不需要的 app，保留需要的
3. 执行：

```bash
bash build.sh
```

如果你只想保留 ERPNext，那就继续用当前默认的 `apps.json`。

---

## 当前对外发布的 tag

现在对外发布只看 AIO：

- `ghcr.io/ashanzzz/erpnext16:aio`
- `ghcr.io/ashanzzz/erpnext16:v16.x.y-aio`

如果是生产环境，优先用固定 tag。
