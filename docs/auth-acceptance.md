# 登录配置与验证

2026-11-19，用户真机 Apple 登录返回 `provider_disabled`。原生 Apple 授权和签名能力已具备，但 Supabase Auth 的 Apple provider=false，Client IDs 未登记应用。签名能力与云端 provider 是两个独立的配置层。

## 变更

通过 Supabase CLI 对指定内测项目先 diff 再最小 push，启用 Apple provider 并登记 `app.bettertogether.betterTogether`。CLI 同组写入 `email_optional=false`；其余未声明的 Auth、数据库和 Storage 设置保持原值。未修改账号、凭据、数据、SMTP 或邮件模板。同步维护仓库 config.toml，防止后续环境遗漏。

原生 iOS 使用 `signInWithIdToken`，nonce 由客户端随机生成、哈希后交 Apple、原值交 Supabase。此流程需要允许的 App ID，不需要为 Web OAuth 生成 client secret。Android 的 Apple 网页登录仍需独立配置 Services ID、有效 client secret 和回调白名单；不能将 iOS 原生成功当成跨平台 OAuth 已通过。

登录页增加受控中文错误映射，不回显供应商正文、URL、token 或异常类型；Apple 取消授权正常回到页面。防止同一帧重复提交，错误区域向辅助功能播报，修改邮箱时清除旧验证码与错误。保留原布局和设计 token。

## 实际验证

- 修复前公开 Auth settings 返回 Apple=false；更新后返回 true。
- 发送故意无效、无真实身份信息的合成 Apple token，Auth 仍拒绝它，且已不返回 provider_disabled；没有放宽 JWT 验证。
- 用户在真机重新完成 Apple 授权后明确回复「已进入首页」，完成真实账号登录闭环。
- 新增 4 项测试：错误脱敏、Apple 取消、错误后重试与同帧防重、邮箱校验与更换邮箱清状态。均通过。
- Flutter analyze 无问题，全量 83 项测试通过，iOS Release 构建成功。日志分别为 `output/qa/auth-fix-analyze.log`、`output/qa/auth-fix-client-tests.log`、`output/qa/auth-fix-release-build.log`。

友好错误提示已包含在新构建的 `app/build/ios/iphoneos/Runner.app` 中。本次未重新安装该产物，用户手机继续使用已登录的 Release 版本。

Apple Android/Web OAuth 不在本次通过范围。邮箱 SMTP 后续处理见下方记录。iOS Apple 配置修复即时生效，无需客户端更新或再次清除账号数据。

## 维护与回滚

更换 Bundle ID 时必须同步 Apple App ID/entitlements 与 Supabase Client IDs。若同时启用 Web OAuth，按官方文档将 Services ID 放在 Client IDs 首位，并在服务端维护 client secret 到期更新；不把它编进 App。对云配置更新使用最小声明的临时 config，先检查 diff，避免整份开发配置覆盖线上值。

回滚配置可只恢复 Apple enabled/Client IDs 的保存值，不删除用户或身份记录；客户端可单独回退 auth_failure/auth_page 变更。已完成的登录会话不应作为部署排错手段被撤销。

依据：[Supabase Sign in with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple)（2026-11-19 查阅）。

## 邮箱验证码排查

同日云端日志确认：两次 `/otp` 请求成功发信，但分别使用 confirmation、magic_link 的登录链接模板，均不包含数字验证码。随后出现浏览器 `GET /verify`，一次性链接再次访问返回过期；App 的验证码表单需要的是 `POST /verify`。另一次发送触发 `over_email_send_rate_limit`。配置实查为未设置 SMTP、内置服务每小时 2 封、8 位验证码。

首次更新模板被 Management API 拒绝：免费项目使用默认邮件服务时不可修改模板（`entitlement_required`）。随后用户通过 `.local/smtp.json` 提供自定义 SMTP，安全连接及身份认证通过，才部署两类验证码模板。部署和回滚见 [邮箱配置手册](email-auth-runbook.md)。

已用隔离测试账号通过管理接口生成一次性验证码（未发送邮件），再以普通客户端权限提交 `type=email`：验证返回 200、会话账号正确、业务 bootstrap 返回 200。日志为 `output/qa/email-otp-cloud-smoke.json`。新增请求/会话测试确认 8 位验证码完整传输，analyze 无问题、全量 85 项测试通过。此证据不代替真实邮件送达与用户在 App 输入验证码的验收。

## SMTP 与模板已部署

2026-11-19 已完成 SMTP TLS 连接和登录认证，未为探测发送邮件。云端 SMTP 字段回读与用户配置一致（密码不输出、不回显）；发信额度设置为每小时 30 封，单邮箱 60 秒冷却保持不变。

confirmation 与 magic_link 正文均已更新为 `{{ .Token }}` 数字验证码，无一次性登录链接。同步变化的两组 custom_contents 元数据经逐项核对，只将这两类模板及主题标为自定义，其他模板保持不变。Apple 登录仍启用，邮箱确认仍必需，OTP 位数与有效期保持原值。无需重新安装 App。

脱敏证据：`output/qa/smtp-connection.json`、`output/qa/smtp-rollout.json`。变更前配置仅保存在权限 600 的 `.local/email-auth-audit/`，用于逐字段回滚。

用户在手机重新获取验证码后明确回复「已收到验证码并进入首页」，真实 SMTP 发信、邮件送达、数字验证码验证、会话与首页闭环通过。配置更新后的隔离账号探测同样验证 OTP 与 bootstrap 均返回 200，见 `output/qa/email-otp-post-smtp-smoke.json`；首次补验因本机 TLS 连接中断未完成，后一次完整探测及用户真机结果分别记录，不将连接中断等同认证失败。
