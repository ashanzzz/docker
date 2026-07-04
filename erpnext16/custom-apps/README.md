# ERPNext16 local custom-apps staging directory

这个目录用来放你**本地要打进镜像的 custom app 源码**。

## 用法

- 把 app 源码直接放到 `erpnext16/custom-apps/<app_name>/`
- 构建时会把这里的内容一起拷进镜像
- 构建流程不会自动拉取任何外部/私有仓库

## 备注

- 如果你暂时不需要 custom app，可以先保留这个目录不放业务代码
- 这个目录只是 staging；真正的业务逻辑请放在可重建的源码里
