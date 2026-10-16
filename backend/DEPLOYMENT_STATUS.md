> 最新部署及安装状态见 [CURRENT_STATUS.md](CURRENT_STATUS.md)；下文保留早期步骤记录。

# 线上部署状态（2026-10-16）

## 已完成

- Supabase 组织 Roam（Free），项目 roam-account-sync。
- Project ref: cafgiqhczacecusugxaj
- API URL: https://cafgiqhczacecusugxaj.supabase.co
- Region: ap-northeast-2 / Seoul，Nano 免费实例；未购买付费升级。
- account-sync.sql 已通过 SQL Editor 执行成功，建立 roam_documents、RLS 及三个 RPC。
- 线上只读查询确认：RLS enabled / forced、匿名表访问被拒绝、authenticated 直接写表被拒绝、两个读写 RPC 对 authenticated 开放，六项均为 true。
- 使用 publishable key 请求 roam_read / roam_write / roam_documents，均返回 HTTP 401 permission denied，符合未登录访问应被拒绝的预期。
- 已确认 Email provider 开启、允许注册、要求邮箱确认、匿名登录关闭。
- iOS/macOS AccountConfig.plist 已接入实际项目 URL 与 publishable key。没有将 secret key、数据库密码或 SMTP 密码写入源码。

## 尚未完成

- Resend 域名 auth.iiife.com 已 Verified。用户已创建受限发信密钥并保存到 Supabase SMTP；控制台显示存储密码已隐藏，SMTP 已启用。Host smtp.resend.com，465，Sender 漫游 <login@auth.iiife.com>。
- Confirm sign up 与 Magic link or OTP 模板均已保存中文验证码模板，使用 {{ .Token }}；尚未进行真实邮件送达测试。
- 已向用户指定测试邮箱发送验证码：Supabase HTTP 200，Resend Delivered。真实邮箱登录、带 JWT 的跨设备同步及真实 CloudKit 图片互通仍待验证。
- Supabase 邮箱验证码长度已保存为 6。两端 EmailLoginReady 已设为字符串 true，以便安装后进行真实登录测试。
- 未上传用户行程、照片；未安装实体设备、推送 Git 或提交 App Store。

## 下一步

等待用户指定测试邮箱，发送验证码并验证登录。不要在聊天或源码记录 SMTP 密钥。
完成 SMTP 与验证码模板后，选择用户指定的测试邮箱验证新账号、已有账号、过期验证码，再把两端 EmailLoginReady 设置为字符串 true。随后验证实际用户隔离、离线冲突、多设备和 iCloud 照片。

控制台：https://supabase.com/dashboard/project/cafgiqhczacecusugxaj
邮件配置：https://supabase.com/dashboard/project/cafgiqhczacecusugxaj/auth/smtp
