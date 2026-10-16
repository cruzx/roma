> 最新部署及安装状态见 [CURRENT_STATUS.md](CURRENT_STATUS.md)；下文保留早期步骤记录。

# 2026-10-16 安装验证

- iPhone 15 Pro Max（00008130-00121D990003401C）：签名 Debug 构建成功，devicectl 覆盖安装 com.xiangchengjin.roam 成功，启动成功。
- Mac Catalyst：签名 Debug 构建成功，安装到 /Applications/漫游-账号同步.app，已正常启动，账号与同步页面可见邮箱和验证码输入框。
- Mac 原版 com.xiangchengjin.roam.mac 保留；新版 com.xiangchengjin.roam 已在界面看到 iCloud 同步的东京、富士山、京都行程。
- 两端安装包 AccountConfig.plist 的 EmailLoginReady 均为字符串 true。服务端已设为 6 位邮箱验证码。
- Resend 测试邮件已 Delivered；实际验证码登录、账号跨设备同步、CloudKit 图片互通仍需登录后验证。
- 未提交 App Store、未推送 Git。开发安装使用 Development CloudKit 环境。
