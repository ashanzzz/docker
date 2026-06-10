# ERPNext16 AIO 资产完整性与自动修复方案

> 目标：把“升级后登录页 HTML 正常，但 `/assets/...` 404 / CSS/JS 缺失”的问题，直接纳入 AIO 构建与启动链路里，做到**升级时只需要 pull/recreate 容器，不需要额外手工跑 bench 命令**。

## 背景

在 `erpnext16` 站点（例如 `http://192.168.8.11:6888/login`）上，当前现象是：

- `GET /login` 能返回 200，登录页 HTML 本身存在
- 但页面引用的关键静态资源会 404，例如：
  - `/assets/frappe/dist/css/login.bundle.*.css`
  - `/assets/frappe/dist/js/frappe-web.bundle.*.js`
  - `/assets/erpnext/dist/css/erpnext-web.bundle.*.css`
- 结果是页面“看起来能打开”，但交互和样式不完整，控制台会报错

这类问题在官方生态里不是孤例，相关参考包括：

- `frappe/frappe#17580` — `Suddenly CSS missing after restart`
- `frappe/frappe#32098` — `Frappe CSS 404`
- `frappe/frappe#38329` — Docker 生产环境下 custom app assets 不被正确服务
- `frappe/frappe_docker#1309` — `404 on css and js files`
- `frappe/frappe_docker#1353` — `ERPNext upgrade makes assets fail`
- `frappe/frappe_docker#1883` — `Asset mismatch between backend and frontend after running bench migrate`

## 现状判断

当前仓库的 AIO 方案已经有一部分“自动 bootstrap”能力：

- `erpnext16/single-aio/Containerfile` 会在 builder stage 里跑 `bench init` / `bench build`
- `erpnext16/single-aio/rootfs/usr/local/bin/entrypoint.sh` 会在启动时把镜像里的 `apps.txt`、`apps.json`、`common_site_config.json`、`assets/` 复制到卷里
- 但现在的 bootstrap 逻辑只处理“文件不存在”的情况，没有处理“文件存在但内容过旧 / 版本不一致”的情况
- healthcheck 目前也只是 `/login`，没有校验关键 asset bundle 是否真的可用

所以，**这不是单纯的登录态问题，也不是简单的“重启就会自动好”问题**。

## 目标设计

### 1. 构建阶段：把资产版本固定下来

在 AIO 镜像构建阶段，除了现有的 `bench build` 之外，再生成一个**资产构建标识**（asset build id / manifest）。

建议这个标识至少包含：

- `ERPNEXT_VERSION`
- `FRAPPE_BRANCH`
- `apps.json` 内容
- custom app 的构建输入摘要（至少是私有 custom app 拉取后的树摘要或构建来源摘要）

生成后，把这个标识和 `sites/assets/` 一起放入镜像侧的 skeleton 目录，例如：

- `/opt/sites-skel/.asset-build-id`
- `/opt/sites-skel/assets/`

这样，镜像本身就携带“这批资产是什么版本”的可比对信息。

### 2. 启动阶段：自动比对，不一致就自愈

在 `entrypoint.sh` 启动时增加一段资产一致性检查：

- 比较镜像侧 `/opt/sites-skel/.asset-build-id`
- 与卷侧 `/home/frappe/frappe-bench/sites/.asset-build-id`
- 如果不存在或不一致：
  1. 重新同步 `sites/assets/`
  2. 同步/覆盖资产标识文件
  3. 清理 Frappe 的 `assets_json` / cache（避免 Redis 里还指向旧 bundle）
  4. 继续启动，而不是让用户手工执行额外步骤

这意味着：

- **升级时**：只要换新镜像并重建容器，启动时会自动把卷里的旧资产修到与镜像一致
- **普通重启时**：如果资产标识一致，就只做轻量检查，不重新折腾资产

### 3. 健康检查：不只看 `/login`

把健康检查从“页面能返回 200”升级为“页面 + 关键 bundle 可达”。

建议至少包括：

- `/login` 返回 200
- 登录页引用的关键 `/assets/...` bundle 也要返回 200

这样可以避免“HTML 200，但 CSS/JS 404”这种半坏状态悄悄溜过去。

## 为什么应该直接写进 AIO 构建，而不是让用户手工操作

因为这个问题本质上是**构建/启动链路问题**，不是用户操作问题。

如果每次升级都要求人手工跑这些命令：

- `bench build`
- `bench clear-cache`
- `frappe.cache.delete("assets_json")`
- 手工检查 assets

那就说明部署链路还没闭环。

正确的目标是：

- build 阶段把资产做好
- 启动阶段自动识别版本不一致
- 有问题自动修复
- 用户升级时只需要：`pull` 新镜像 + 重建容器

## 计划修改的文件

### 构建侧
- `erpnext16/single-aio/Containerfile`
  - 在 builder stage 里生成 asset build id / manifest
  - 把标识写入 `/opt/sites-skel`

### 启动侧
- `erpnext16/single-aio/rootfs/usr/local/bin/entrypoint.sh`
  - 启动时比对镜像侧与卷侧 asset build id
  - 不一致时同步 `sites/assets/`
  - 清理 `assets_json` / cache
  - 保持“无需手工额外操作”的升级体验

### 文档侧
- `erpnext16/single-aio/README.md`
  - 补充升级说明：普通升级无需额外 bench 手工步骤
  - 说明 assets 校验与自动修复是镜像内建行为
- `erpnext16/docs/asset-integrity-aio.md`（本文档）
  - 作为后续实现的设计依据

## 推荐实现顺序

1. **先加 asset build id / manifest**
   - 不改业务逻辑，只加可比对标识
2. **再加启动时的一致性检查与同步**
   - 用标识判断是否需要同步
3. **再清理 cache / assets_json**
   - 防止旧缓存继续指向旧 bundle
4. **最后补 healthcheck**
   - 确保“页面能开”与“资源完整”一起过关
5. **更新 README**
   - 把升级方式写清楚

## 验收标准

实现完成后，应该满足：

- 新镜像启动后，不需要用户额外跑 `bench build`
- 升级后，旧卷里的 assets 会自动与新镜像对齐
- `/login` 页面加载正常，关键 bundle 也能 200
- 如果资产不一致，容器会自动修复或明确报错，不会静默留下“HTML 正常但 CSS/JS 404”的半坏状态

## 非目标

- 不是把每次重启都变成完整重建
- 不是让用户手工去清 cache / 跑 bench 命令
- 不是改成多容器方案
- 不是把问题归结为“登录态”或“token”

## 备注

这份方案的重点是：**把资产完整性从“人工排查项”变成“镜像内建能力”**。

如果你确认“可以实现了”，下一步就直接改：

- `erpnext16/single-aio/Containerfile`
- `erpnext16/single-aio/rootfs/usr/local/bin/entrypoint.sh`
- `erpnext16/single-aio/README.md`

然后我会按这个设计把自动校验/自愈链路写进去。
