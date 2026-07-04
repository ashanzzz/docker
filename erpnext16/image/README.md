# ERPNext16 image inputs

这个目录只保留 **AIO 构建输入**。

## 当前职责

- `apps.json` / `apps.json.example`：官方 app 清单输入
- `build.sh` / `Containerfile`：本地构建辅助
- `custom-apps/`：可选的本地 custom app 暂存内容

## 本地构建方式

如果你要把 custom app 一起打进镜像：

1. 先把 custom app 源码放到 `erpnext16/custom-apps/`
2. 再执行：

```bash
cd erpnext16/image
bash build.sh
```

构建流程不会自动同步任何外部仓库，也不需要 token。
