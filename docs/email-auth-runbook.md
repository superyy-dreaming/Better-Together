# 邮箱验证码配置与验收

## 问题边界

App 使用 `signInWithOtp` 发送请求，再使用 `verifyOTP(type: email)` 提交数字验证码。新用户使用 confirmation 模板，已有用户使用 magic_link 模板。两者必须包含 `{{ .Token }}`；链接模板会使用户进入浏览器，并可能在链接再次访问时收到一次性凭证已失效的错误。

Supabase 内置发信服务仅面向项目成员，当前每小时最多 2 封。普通内测用户必须接入可用的自定义 SMTP；修改模板不会解除内置服务的收件人及额度限制。

## 最小部署与回滚

1. 核对内测项目标识，通过 Management API 读取当前 Auth 配置；备份保存至权限 600 的 `.local/email-auth-audit/`，不打印值。
2. 模板更新只修改 confirmation 与 magic_link 的正文及主题。使用 `supabase/templates/email_otp.html`，不附加一次性登录链接。保持线上 8 位验证码与有效期，不以更改有效期掩盖邮件链路问题。本地 config.toml 的位数和有效期已与线上当前值同步。免费项目使用默认邮件服务时，模板更新可能返回 entitlement_required；须先完成第 3 步的自定义 SMTP 配置，再执行模板更新，无需为此升级套餐。
3. SMTP 通过 `.local/smtp.json` 注入。核对服务器、端口、发件人及凭据；不编译进 App，不上传为客户端配置。完成安全连接与 SMTP 身份认证后，只更新 SMTP 字段；初始发信额度按官方自定义 SMTP 基线设为每小时 30 封，保留单地址 60 秒冷却，不修改 Apple、JWT、用户确认或注册策略。
4. 每次更新前重读受影响字段，发现并发修改则停止；PATCH 后重读确认，并检查其他字段未变。模板修改会同步更新 `mailer_templates_custom_contents` 与 `mailer_subjects_custom_contents` 中对应模板的布尔标记，必须核对只有目标模板变化，不将所有元数据差异笼统放行。回滚只恢复该次变更字段的备份，不整份覆盖 Auth 配置，不重置账号或撤销登录会话。
5. 使用隔离测试账号验证数字验证码产生会话及业务接口可用，验证码与会话仅留内存。该步骤不等于邮件送达；真实送达和 App 输入验证码仍需用户本人测试。错误日志只记录状态与脱敏代码。

## 依据

- [Supabase Passwordless email sign-in](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Supabase Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Supabase Email Templates](https://supabase.com/docs/guides/local-development/customizing-email-templates)
- [Supabase Auth 配置 API](https://supabase.com/docs/reference/api/v1-update-auth-service-config)

2026-11-19 查阅。上线结果另记于 [登录验收](auth-acceptance.md)。
