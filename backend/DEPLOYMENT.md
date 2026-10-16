# 邮箱账号同步 + iCloud 图片部署

当前实现：邮箱账号、行程文字、安排、地点、路线、排序、垃圾桶和手账清单由 Supabase 保存；自选封面、安排照片、网页预览图、手账 PNG 仅进入设备缓存与私人 CloudKit。账号服务器只接收图片引用，不接收图片字节。账号数据库已部署到 cafgiqhczacecusugxaj（首尔免费项目）；SMTP 尚未配置，尚不能使用邮箱验证码登录。部署实况见 DEPLOYMENT_STATUS.md。

## 部署步骤

1. 在自己的 Supabase 账户创建项目，确认区域、套餐、备份和目标用户网络可达性。
2. 在 SQL Editor 执行 `account-sync.sql` 一次性初始迁移。本次账号功能从未部署，因此不需要线上旧版图片数据迁移。若自行部署过前一版，先备份并制定数据迁移，不能直接重复执行此 SQL。
3. 开启 Email 登录/注册，配置自有 SMTP 和发信域名，验证码邮件模板包含 `{{ .Token }}`。实际测试新注册、已有账号、错误/过期验证码和限流。
4. 把 HTTPS 项目 URL 与 publishable key 填进 iOS/macOS 的 `Roam/AccountConfig.plist`，两端相同。不要填 service_role、secret key 或 SMTP 密码。
5. 配置并实测 SMTP、验证码模板后，将两端 AccountConfig.plist 的 EmailLoginReady 改为字符串 true，才开放邮件登录入口。
6. 在 Apple 开发者账户保留两个 App 对 `iCloud.com.xiangchengjin.roam` 的 CloudKit 权限、签名和生产 schema。图片沿用 `RoamLibrary` 类型的 `payload` CKAsset 字段；发布前确认生产环境可写。
7. 用两台实体设备完成下面的验收，再更新隐私政策和 App Store 隐私申报。

官方参考：
- https://supabase.com/docs/guides/auth/auth-email-passwordless
- https://supabase.com/docs/guides/auth/auth-email-templates
- https://supabase.com/docs/guides/database/postgres/row-level-security

## 使用方式与边界

设置 → 账号与同步 → 邮箱验证码登录 → 启用账号同步。可选复制现有行程/手账，原 iCloud 数据保留。首次迁移写临时目录成功后才启用；已有账号目录不覆盖。**切换后立即完全退出并重开 App**，当前进程仍使用原资料空间。

- 同一个漫游账号：同步行程文字和图片引用。
- 同一个 Apple ID：才能读取该 Apple ID 私人 CloudKit 中的照片。不同 Apple ID 登录同一漫游账号，文字仍同步，缺失的照片显示为等待 iCloud；不会向服务器补传图片。
- 账号行程先同步文字，再独立重试 iCloud 照片。iCloud 登录、网络或容量错误不会阻止文字同步，也不会清除本机照片和远端引用。
- 图片按内容摘要缓存，CloudKit 记录按漫游账号隔离。每个本机账号空间绑定首次使用的 Apple ID；检测到 Apple ID 更换时暂停该空间的图片同步，避免把已缓存的私人照片自动上传到另一个 Apple ID。
- 手账仍沿用“图片就绪后发布清单”的完整性规则：其文字/几何清单进账号服务，PNG 进 iCloud。iCloud 故障可能延迟整个手账的同步，但不会阻塞行程文字。
- 离线编辑保留；运行时每 30 秒重试，同一旅行冲突保留副本，上传期间新修改不会误清除。App 被系统终止后不保证后台实时同步。
- 缺图时编辑文字仍保留引用；封面/安排图片下载完成后恢复显示。图片未就绪时编辑器不能展示或精细管理尚未下载的图片，应等图片就绪后再整理。
- 首页背景和未归档分享收集箱仍为本机资料。

## 存储、安全与费用

账号服务继续使用 base64 包装的 JSON 文档，但不包含照片二进制。服务端拒绝 `image/*` 文档，以及 JSON 内非空的 `coverPhoto`、`photos`、`imageData` 字段；客户端也验证这些约束。数据库按 auth.uid() 隔离，写入仅通过带版本校验的 RPC。

现有限额：单文档 64 MiB，单账号 256 MiB（base64 后），属于保护上限，不代表购买了这些容量。账号数据库、验证码邮件和备份是否收费取决于供应商套餐和用量。图片占用用户 iCloud 相关存储配额；这不等于保证整个服务永远免费。

图片不会自动清理云端孤立记录，避免删除离线设备仍引用的照片。删除漫游云端账号只删除 Supabase 账号、文字和引用，**不删除本机副本和 iCloud 图片**。隐私政策必须明确这一点，以及云备份保留周期。后续若要提供 iCloud 图片清理，应单独实现带确认的清理功能。

凭据保存在设备钥匙串。退出登录不自动回退到 iCloud 文字同步；可以在设置切回原 iCloud 资料空间，重启生效。预合并本机快照不能替代服务器备份。

## 发布前验收

1. 相同漫游账号 + 相同 Apple ID：iPhone 新增封面、安排照片、链接图，Mac 验证文字和图片；第二台 iPhone 验证手账。
2. 同漫游账号、不同 Apple ID：文字同步；图片缺失提示，不应上传到账号数据库。检查服务端文档不含图片字节。
3. 关闭 iCloud/断网/配额不足：行程文字仍同步；照片留在本机，恢复后重试成功。
4. 在缺图设备编辑文字，稍后恢复 iCloud，原图片引用和图片仍在；删除/替换照片不会复活旧图。
5. 两台设备同时编辑、删除与离线编辑碰撞：保留冲突副本及相应图片引用。
6. 用户 A/B 互相无法读取账号文档；本机切换账号需重启，原空间保留。
7. 测试 SMTP、JWT 过期刷新、限流、账号删除、CloudKit 开发/生产环境与真实网络。
8. 更新隐私政策、审核说明和账号删除说明。

## 本地验证

`backend/tests` 中运行 `npm ci && node permissions.mjs`。PGlite 使用 auth 测试替身，仅验证 PostgreSQL 权限/版本条件/拒绝图片，不替代真实 JWT 或 SMTP。

Xcode 运行 AccountSyncTests、AccountPhotoTests、CloudLedgerTests、JournalCloudTests。实测结果见 VALIDATION.md。
