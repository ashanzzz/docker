# Docker 项目 SOP

这份文档是这个仓库的长期约定。

目标很简单：
- 能在 Unraid / Linux 上落地
- 尽量少折腾
- 版本和来源说得清楚
- 以后不管是人还是 AI，接手时都不会猜来猜去

给 AI 的额外说明在 `AGENTS.md`。

---

## 1. 总原则

1. **先跟官方，再做收敛。**
   - 能基于官方镜像、官方源码、官方文档，就不要自己发明一套。
   - 但最终交付可以按 Unraid 使用习惯收敛成更简单的形态，比如单容器 AIO。

2. **对用户暴露的用法要尽量简单。**
   - 能一条 `docker run` 解决，就不要先上复杂 compose。
   - 能给出固定目录、固定端口规则，就不要让用户到处猜。

3. **版本要可追溯。**
   - 每个镜像最好都能回答两个问题：
     - 它跟的是哪个上游版本？
     - 它是滚动 tag，还是固定 tag？

4. **README 不是摆设。**
   - 每个子项目至少要写清楚：它是什么、它不是什么、怎么跑、怎么升级、上游参考是谁。

---

## 2. 项目怎么命名

### 2.1 目录名

- 统一用小写。
- 优先用这两种风格：
  - `产品名`
  - `产品名 + 主版本号`

例子：
- `openclaw`
- `erpnext16`

### 2.2 什么时候把版本写进目录名

满足下面任一情况，就直接写进目录名：
- 这个项目明确绑定某个大版本线
- 不同大版本未来可能并存
- 你希望目录名本身就告诉接手的人“这不是泛用版”

例子：
- `erpnext16` 是对的
- 不要把它叫成过于泛的 `erpnext`，否则后面 v17/v18 很容易混

### 2.3 变体目录怎么命名

如果同一产品下面有不同交付形态，用子目录区分，不要把根目录搞得太花：
- `single-aio/`
- `image/`
- `upstream/`

这类名字要表达用途，不要表达情绪。

---

## 3. AIO 脚本怎么写

这里说的 AIO，是给“我只想跑一个容器”的场景准备的。

### 3.1 适用场景

适合：
- Unraid 用户
- 单机部署
- 希望用一条 `docker run` 跑起来

不适合：
- 明确追求官方多服务拓扑
- 后续要做大规模横向扩容
- 服务边界必须拆得很细

### 3.2 AIO 目录结构

建议这样放：

```text
<project>/
  README.md
  single-aio/
    Containerfile
    README.md
    rootfs/
```

### 3.3 AIO 镜像的基本要求

1. **容器内端口固定，宿主机端口外部映射。**
   - 容器里固定监听一个端口，比如 `8080`
   - 宿主机用 `-p <HOST_PORT>:8080`
   - 不要把内部端口也做成一堆变量，没必要

2. **初始化逻辑必须可重复执行。**
   - entrypoint 第一次跑能初始化
   - 第二次跑不要把已有数据搞坏
   - 能判断“已初始化/未初始化”

3. **卷挂载只暴露真正需要持久化的目录。**
   - 不要一股脑把整棵应用目录都映射出去
   - 只挂站点数据、数据库、Redis、配置这类必要目录

4. **镜像内要留默认骨架。**
   - 如果用户挂空 volume，会把镜像内原始内容盖掉
   - 需要像 `sites-skel` 这种兜底目录时，就明确保留

5. **不要依赖用户手动补关键配置。**
   - 能在 entrypoint 自动补，就自动补
   - 能在容器里自校验，就自校验

### 3.4 AIO README 要写什么

至少包括：
- 最简 `docker run`
- 持久化目录说明
- 必填环境变量
- 默认端口规则
- 升级方式
- 明确告知哪些文件不要外挂覆盖

---

## 4. 如何写符合这个仓库习惯的 Docker 镜像

### 4.1 先写清楚它是“官方派生”，还是“部署脚本”

这两类要分开：

1. **派生镜像 / 构建输入**
   - 例：`erpnext16/image`
   - 特点：基于官方镜像或官方源码的构建输入，给最终交付镜像提供依赖和版本约束

2. **部署入口 / 运行入口**
   - 例：`erpnext16/single-aio`
   - 特点：重点是让用户直接跑起来，而不是暴露一堆内部构建细节

README 一开始就要讲明白，别让人混。

### 4.2 镜像 Dockerfile 的写法

#### 派生官方镜像时

- 第一行就让人看到来源
- 增量改动尽量少
- 如果只是加系统包，把包名单独放到 `packages.txt`

例子：

```dockerfile
ARG FRAPPE_IMAGE_TAG=version-16
FROM frappe/build:${FRAPPE_IMAGE_TAG} AS builder
```

#### 基于官方源码构建时

- 把“基础镜像 tag”和“源码分支/源码 tag”分开
- 这两个概念不要混成一个变量

例如：
- `FRAPPE_IMAGE_TAG=version-16`
- `FRAPPE_BRANCH=version-16` 或 `v16.13.0`

这样以后要固定源码 tag 时，不会把基础镜像逻辑一起打乱。

### 4.3 包和依赖的原则

- 尽量加“必要依赖”，不要顺手塞一堆调试工具
- 如果为了中文环境，要明确写清楚 locale / fonts 是有意加的
- 如果某个大型依赖会显著增大镜像体积，README 要提前说

### 4.4 这个仓库偏好的镜像风格

1. 注释写清楚来源和目的
2. 变量名直白
3. 增量尽量小
4. 用户侧运行方式尽量简单
5. 文档里明确说清“这镜像是什么 / 不是什么”

---

## 5. 如何上传到 GitHub Container Registry（GHCR）

### 5.1 工作流固定骨架

一个正常的镜像 workflow，至少要有这些步骤：

1. `actions/checkout`
2. 解析上游版本
3. 必要时验证上游 tag 是否存在
4. `docker/setup-qemu-action`
5. `docker/setup-buildx-action`
6. `docker/login-action` 登录 GHCR
7. `docker/build-push-action` 构建并推送
8. 可选：打 Git tag / 发 GitHub Release

### 5.2 登录 GHCR 的标准写法

```yaml
- name: Login GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

### 5.3 推送 tag 的原则

每次推送最好至少有两类 tag：

1. **固定 tag**
   - 用来精确回滚
   - 例：`v16.13.0-aio`
   - 例：`33.0.2-apache-full`

2. **滚动 tag**
   - 用来给图省事的人
   - 例：`latest`
   - 例：`aio`
   - 例：`33-apache-full`

### 5.4 Release body 的坑

GitHub Actions 的 `with:` 不是 shell。

所以这种写法不可靠：

```yaml
body: |
  $(cat packages.txt)
```

这通常不会执行命令，而是把字面量写进去。

正确做法：
- 先在前一个 `run` 步骤里生成内容
- 写到 step output 或临时文件
- 再传给 release action

---

## 6. 版本号、latest、代码命名怎么定

### 6.1 版本号

优先跟上游版本，不自己编花里胡哨的版本系统。

例子：
- ERPNext：`v16.13.0`
- OpenClaw：按上游实际 tag 或版本文件取值

如果是变体镜像，就在后缀上表达：
- `v16.13.0-aio`

### 6.2 `latest` 的规则

- `latest` 只是便利标签，不是生产锚点
- 文档里可以展示 `latest`
- 但生产建议永远写固定 tag

### 6.3 推荐的 tag 组合

#### ERPNext AIO

- 固定：`ghcr.io/<owner>/erpnext16:v16.x.y-aio`
- 滚动：`ghcr.io/<owner>/erpnext16:aio`

### 6.4 Git tag 命名

如果一个仓库里有多个子项目，Git tag 不要太泛。

建议：
- `erpnext16-v16.13.0-aio`
- `openclaw-v1.2.3`

这样看 tag 就知道是哪个子项目，不会互相打架。

---

## 7. 代码和文件命名规则

### 7.1 文件名

- 统一小写
- 用连字符分隔
- 变量文件、约定文件保留行业常见写法

例子：
- `erpnext16-single-container-aio.yml`
- `docker-compose.example.yml`
- `packages.txt`
- `apps.json`

### 7.2 脚本名

脚本名保持短、直白：
- `run.sh`
- `build.sh`

不要写成：
- `final-build-new.sh`
- `run-all-fixed.sh`

### 7.3 版本文件名

如果项目有一个单独版本文件，就直接叫：
- `OPENCLAW_VERSION`

不要把版本散落到三四个 README 里让人猜。

---

## 8. 工作流怎么命名

### 8.1 workflow 文件名

规则：

```text
<project>-<action>.yml
```

例子：
- `erpnext16-single-container-aio.yml`
- `openclaw-sync-and-build.yml`

### 8.2 workflow 显示名

`name:` 给人看，允许更自然一点，但也别写得太虚。

推荐风格：
- `Build ERPNext16 AIO image (single container)`
- `openclaw sync & build`

### 8.3 action 命名建议

常用动作词就这些，够用了：
- `build`
- `sync`
- `sync-build`
- `custom-image`
- `release`

别为了“高级感”发明新词。

---

## 9. 新项目落地时的最小清单

一个新子项目，至少补齐这些：

- 目录
- `README.md`
- Dockerfile / Containerfile
- 必要的版本文件或 `apps.json`
- 一个能工作的 workflow
- 上游参考链接
- tag 规则说明

如果是 AIO，再加：
- `single-aio/README.md`
- entrypoint / rootfs
- 卷挂载说明

---

## 10. 给后续维护者的一句话

这个仓库不是拿来炫技巧的。

优先级一直是：
1. 用户能跑起来
2. 版本能说清楚
3. 出问题时知道该去哪里查
4. 以后改的人不用重新发明一遍
