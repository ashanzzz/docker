# ERPNext16 standard image

这个目录构建的是 **标准 ERPNext 16 镜像**，不是单容器 AIO。

它的用途主要有三种：
- 给多容器部署复用同一个 ERPNext 镜像
- 在镜像里预烘焙官方 apps
- 作为后续衍生方案的基础镜像

如果你要的是“Unraid 上只跑一个容器”，请直接看：
- `erpnext16/single-aio/README.md`

---

## 这个目录里有什么

- `Containerfile`：标准镜像构建定义
- `build.sh`：本地构建脚本
- `apps.json`：当前实际使用的 app 列表
- `apps.json.example`：可直接复制修改的示例

---

## 当前版本策略

当前仓库默认策略是：

- `FRAPPE_IMAGE_TAG=version-16`
- `FRAPPE_BRANCH=<与 ERPNext 相同的精确 v16.x.y tag>`
- ERPNext app 在 workflow 里尽量 pin 到发现到的 `v16.x.y`

这意味着：
- 基础镜像仍然跟 `version-16` 主版本线
- Frappe 源码和 ERPNext app 要求对齐到同一个精确 tag

如果 workflow 找到了 ERPNext 的 `v16.x.y`，却找不到官方 `frappe/frappe` 的同名 tag，构建会直接失败，而不是自动回退到 `version-16` 分支。

---

## 本地构建

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
- 但 GitHub Actions 自动发布流程已经更严格，要求 `FRAPPE_BRANCH` 和 ERPNext 使用同一个精确 `v16.x.y` tag。
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

## tag 规则

### 标准镜像

- 滚动：`ghcr.io/ashanzzz/erpnext16:latest`
- 固定：`ghcr.io/ashanzzz/erpnext16:v16.x.y`

### 自定义镜像

- `ghcr.io/ashanzzz/erpnext16:v16-custom`
- `ghcr.io/ashanzzz/erpnext16:v16-hrms`

如果是生产环境，优先用固定 tag。

---

## 和 AIO 的区别

这个目录构建的是标准镜像。

它适合：
- 多容器部署
- 自定义官方 apps
- 作为别的部署方案基础镜像

它不负责：
- 单容器内置 MariaDB + Redis + Nginx 的 AIO 运行方式

那个在：
- `erpnext16/single-aio/`
