# ERPNext16 custom app staging directory

这个目录不再保存业务 custom app 的源码主副本。

它现在只是 **AIO 构建前的暂存目录**：

- GitHub Actions 会先从私有仓库 `ashanzzz/erpnext-private-customizations` 拉取 `erpnext16/custom-apps/`
- 本地手动构建时，可通过 `erpnext16/scripts/fetch-private-customizations.sh` 同步同样内容

请不要再把业务代码直接维护在这个仓库里。
