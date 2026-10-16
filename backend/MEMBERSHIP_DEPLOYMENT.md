> 最新部署及安装状态见 [CURRENT_STATUS.md](CURRENT_STATUS.md)；下文保留早期步骤记录。

# 账号同步年费会员（2026-10-16）

用户确认：中国大陆每年人民币 18 元，Apple 自动续订订阅；不是买断。
产品 ID：`com.xiangchengjin.roam.sync.annual`。归属统一 App `6818919203`（bundle `com.xiangchengjin.roam`），不是已停售的独立 Mac App。

## 已实现

- StoreKit 2 商品动态价格、年度周期核对、购买 pending/cancel/success、交易更新、恢复购买、订阅管理、条款和隐私链接。
- 必须登录邮箱账号后购买，以 Supabase 用户 UUID 作为 appAccountToken。恢复到不同漫游账号会被拒绝。不要启用家庭共享。
- 客户端向 Edge Function 提交 transactionId，服务器使用 Apple 官方 App Store Server Library 查询订阅当前状态并校验 JWS、证书链、bundle/product/account/environment/type/ownership。客户端不能声明已付款。
- 服务器支持有效订阅与 Apple 宽限期；关闭自动续订不影响当前周期；过期、扣款重试无宽限期、退款撤销不能同步。
- SQL 对读写 RPC 及直接 REST SELECT 都强制校验会员。底层原写入函数撤销客户端执行权限。会员表仅 service_role 写入。
- 权益缓存最多 15 分钟且不超过付费期限；Apple 通知先使缓存失效，再查询当前状态，通知乱序不直接覆盖权益。查询失败停止同步并保留本机数据。
- 本地使用、原 iCloud 同步免费；会员到期不删除资料。账号删除不要求会员，取消 Apple 订阅须另在 Apple 设置操作。

## 上线步骤（尚未执行）

1. 登录 App Store Connect，统一 App 内创建自动续订订阅组“账号同步会员”，创建上述产品，期限 1 年，中国大陆价格选择 ¥18，其他地区按 App Store 换算。显示名称“账号同步年费会员”，说明“行程文字与图片引用跨设备账号同步，照片使用 iCloud”。上传购买页审核截图，补充审核说明，检查付费协议/税务/银行状态。不得代用户接受法律协议或填写财务信息。
2. Users and Access → Integrations → In-App Purchase 创建服务端 API 密钥（由用户创建，.p8 只存服务端 secrets），记录 key ID、issuer ID。不要用普通客户端 API key 代替。
3. 从 Apple PKI 官方站点下载 Apple Root Certificates（DER），base64 后组成 JSON 数组配置到 `APPLE_ROOT_CA_BASE64_JSON`。不得接受客户端传入根证书。
4. Edge Functions secrets：`APPLE_PRIVATE_KEY`、`APPLE_KEY_ID`、`APPLE_ISSUER_ID`、`APPLE_APP_ID=6818919203`、`APPLE_ROOT_CA_BASE64_JSON`。Supabase 内置 `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`。测试期间 `APPLE_ALLOW_SANDBOX=true`，是否长期允许 TestFlight Sandbox 须明确规划。所有私钥禁止进入 App、Git 或聊天。
5. 使用 `backend/supabase` 工程部署 `roam-membership`、`apple-notifications`（config.toml 已设置网关 JWT 关闭：前者在函数内 auth.getUser 验证 JWT，后者验证 Apple JWS）。生产部署需要校验运行时官方 Node 库兼容性和出站 OCSP 请求。
6. 在数据库执行 `membership.sql` 一次，前提是已部署 `account-sync.sql`。这是强制付费切换：旧客户端也会停止免费账号同步。应与服务端、商品准备完成和新版本发布配合，避免无法购买时直接锁住用户。不要重新执行 account-sync.sql。
7. App Store Server Notifications V2 配置到 `https://cafgiqhczacecusugxaj.supabase.co/functions/v1/apple-notifications`，配置生产与沙盒 URL，发送 Apple 测试通知。
8. 沙盒验证实际新购、恢复、两台设备同邮箱权益、不同邮箱拒绝、取消续订仍有效、过期拒绝、退款即时通知、通知重试、旧通知不复活、服务异常不扣款、不删除资料。SQL/纯策略测试不能替代这些验证。
9. 首次订阅随 App 新版本提交审核；未获批不可宣称正式可付款。代码中价格使用 Apple displayPrice，不硬编码人民币向所有地区展示。

## 当前限制

已写代码及迁移，尚未部署会员强制校验、未创建 ASC 商品/密钥、未验证真实 Apple 付款。目前线上仍是上一版账号同步。新会员版本未替换已安装 App，避免购买服务未配置时锁住用户。

## 数据与删除

删除漫游账号会删除服务端权益关联，但不会取消 Apple 订阅；须先提示取消订阅。重新注册产生新 UUID，旧购买无法自动绑定新账号，需人工核验恢复（不应允许客户端修改 appAccountToken）。本版不自动转移购买，会员页面说明账号绑定。

## 本地验证结果

2026-10-16：iOS、Mac Catalyst 构建通过；账号 10 项单元测试 + 1 项会员入口界面测试通过；会员 SQL 15 项测试和 Apple 权益策略 15 项测试通过；原账号 SQL 14 项回归测试通过；两个 Edge Functions 通过 Deno 类型检查。真实 Apple 沙盒支付和 Edge 生产运行尚未验证。

## App Store Connect 实际配置（2026-10-16）

已创建订阅群组 22484169（账号同步会员）；年度商品 Apple ID 6823544188，product ID com.xiangchengjin.roam.sync.annual，周期 1 年。已保存中国大陆 CNY ¥18.00 和 Apple 自动换算的 175 地区价格表，以及简体中文显示名称/说明。未提交审核。

剩余：年度预付供应地区、群组本地化、英文说明（如适用）、关闭不兼容的 App 外简化购买/多名额购买、审核截屏、Apple 交易验证密钥、Edge 函数与 SQL 部署、沙盒验证。账户主页提示新版 Apple Developer Program 许可协议需由账户持有人查阅接受，影响版本提交。
