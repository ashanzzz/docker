# OpenClaw runtime image

这个目录是 `openclaw` 的运行时增强镜像。

目标：
- 跟随官方 `openclaw/openclaw` 版本
- 保留中文环境、Chromium 和常用排障工具
- 每天自动检查官方版本
- 如果本地版本文件落后，就更新本地版本文件并重新构建 GHCR 镜像

---

## 官方来源

- 官方项目：<https://github.com/openclaw/openclaw>
- 官方基础镜像：`ghcr.io/openclaw/openclaw`
- 当前仓库还会同步：`openclaw/upstream/docker-setup.sh`

版本判断规则：
- 优先取 GitHub latest release
- 如果 release 不可用，再回退到 tags

---

## 本地版本文件

文件：`openclaw/OPENCLAW_VERSION`

workflow 每天会做这件事：
1. 读取官方版本
2. 对比 `OPENCLAW_VERSION`
3. 如果不一致，更新文件并提交
4. 然后构建并推送镜像

---

## 对外镜像 tag

- `ghcr.io/ashanzzz/openclaw:latest`
- `ghcr.io/ashanzzz/openclaw:<official-version>`
- `ghcr.io/ashanzzz/openclaw:<official-version>-r<run-number>`

生产建议用固定 tag。

---

## 镜像里额外加了什么

- Chromium
- 中文字体
- locale
- 常用排障工具
- 浏览器相关默认环境变量

它不是重打包 OpenClaw 源码，只是在官方镜像基础上补运行时环境。
