# 混合同步验证记录（2026-10-16）

基于 cruzx/roma `1e725c1`。账号服务器保存文字/图片引用，CloudKit 保存图片；已部署账号数据库，SMTP 尚未配置；未推送、未安装实体设备或提交审核。线上实况见 DEPLOYMENT_STATUS.md。

- iOS 最终代码构建和 40 项单元测试通过：AccountPhotoTests 5、AccountSyncTests 9、CloudLedgerTests 7、JournalCloudTests 19。
- iOS AccountSettingsUITests 界面测试通过：未配置服务时显示说明，不提供登录发送入口。
- Mac Catalyst 构建通过。
- PostgreSQL/PGlite 14 项检查通过：匿名拒绝、账号隔离、CAS 版本冲突、禁止直接写表、拒绝图片文档、拒绝嵌入图片与非 JSON、账号删除级联及其他用户保留。
- Git 差异格式检查通过。

图片单元测试覆盖：封面/安排照片/链接预览剥离，缓存还原、缺图时文字编辑保留引用、显式删除、非法引用、垃圾桶图片不能上传账号服务。

数据库使用 auth 测试替身。真实 SMTP/JWT、CloudKit 权限与生产 schema、两个 Apple ID、多台实体设备、网络中断和配额耗尽尚未实测，不宣称已验证线上稳定性。手账仍要求图片就绪后发布清单，详见 DEPLOYMENT.md。

构建/测试在系统临时目录完成，避免 Documents 的 iCloud 占位文件阻塞编译。日志已随交付保存于 outputs/账号同步验证/。

## 实际项目配置后的复测

账号服务 10 项单元测试及 1 项界面测试通过，包含 SMTP 未就绪时拒绝发送验证码。Mac Catalyst 配置后构建通过。尚未进行真实验证码登录和带 JWT 的跨设备测试。
