# AGENTS.md

这份文件给后续 AI 用。

仓库类型：Docker 项目集合，不是单一产品。
主要方向：Unraid / Linux 落地、派生镜像、自动同步上游、GHCR 发布。

---

## 1. 你改代码前先做什么

1. 先看目标子目录的 `README.md`
2. 如果涉及镜像构建，再看对应 `Dockerfile` / `Containerfile`
3. 如果涉及自动发布，再看 `.github/workflows/*.yml`
4. 如果涉及版本同步，确认版本来源是不是官方唯一来源

不要一上来就改 workflow。

---

## 2. 这个仓库的稳定约定

### 2.1 目录命名

- 目录名保持小写
- 版本线明确时，把主版本号写进目录名
- 例：`erpnext16`

### 2.2 用户侧体验

- 优先让用户用最少命令跑起来
- Unraid 场景优先考虑 `docker run`
- 如果有 AIO 方案，内部端口固定，宿主机端口走映射

### 2.3 版本规则

- 固定 tag 用来回滚和生产 pin
- moving tag 用来图省事
- 不要只留 `latest`

### 2.4 上游优先

- 能跟官方镜像就跟官方镜像
- 能跟官方源码分支/tag 就跟官方源码
- README 里要写官方参考地址

---

## 3. 子项目特定规则

### 3.1 `erpnext16/`

- 这是版本绑定目录，不要随便改名
- 有两条线：
  - `image/`：多容器或通用镜像构建
  - `single-aio/`：单容器 AIO
- 当前命名习惯：
  - 镜像仓库名保留 `erpnext16`
  - AIO 用 tag 后缀区分：`aio` / `v16.x.y-aio`
- 官方参考：
  - `frappe/frappe_docker`
  - `frappe/erpnext` `version-16`
  - `frappe/frappe` `version-16`

### 3.2 `nextcloud/`

- `nextcloud/` 是部署工程
- `nextcloud/image-full/` 是派生镜像
- 当前版本线跟 `33.x`
- 当前 tag 习惯：
  - 固定：`33.x.y-apache-full`
  - 通道：`33-apache-full`
  - 便利：`latest`

### 3.3 `openclaw/`

- 会同步上游 `docker-setup.sh`
- `openclaw/upstream/` 是上游快照区，不要乱塞别的文件

---

## 4. 改 workflow 时必须检查的事

1. YAML 里引用的路径，本地是否真的存在
2. `context` 和 `file` 是否指向同一套构建内容
3. 上游版本解析逻辑是否有唯一来源
4. 构建 tag 是否同时包含：
   - 固定 tag
   - moving tag
5. 文档里的 tag 说明有没有跟着更新

---

## 5. 已知坑

### 5.1 GitHub Actions `with:` 不是 shell

不要这样写：

```yaml
body: |
  $(cat packages.txt)
```

这不会按 shell 执行。

正确做法：
- 先在 `run` 步骤生成内容
- 再传给后续 action

### 5.2 Markdown 没有 LSP 不等于文档有错

如果工具提示：

`No LSP server configured for extension: .md`

这只是当前环境没配 Markdown LSP，不是文档语法错误。

### 5.3 不要把 `latest` 当成生产版本说明

README 可以展示 `latest`。
但只要是生产建议，就要给固定 tag。

---

## 6. 你写文档时的语气

- 说人话
- 少用宣传腔
- 少写空洞口号
- 先写“怎么用”，再写“为什么这样做”
- 如果这是偏 Unraid 的收敛方案，要明确告诉读者它和官方方案的关系

---

## 7. 你交付前的自检清单

- [ ] README 写了它是什么 / 不是什么
- [ ] 官方参考地址已补齐
- [ ] 固定 tag 和 moving tag 都有
- [ ] workflow 的本地路径真实存在
- [ ] 用户运行方式尽量简单
- [ ] 如果是 AIO，卷挂载和升级方式已写清楚
- [ ] 没有把用户已有目录名随手改掉

---

## 8. 最后一点

这个仓库偏实用，不偏炫技。

如果你在两个方案里选：
- 一个更优雅
- 一个更稳、更容易解释、更容易让用户照着抄

默认选后者。
