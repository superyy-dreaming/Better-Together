# 自定义 AI 出站请求安全审核

审核日期：2026-11-18。范围是本地代码、测试和官方文档的只读复核；没有修改云端网络策略，没有读取真实密钥，也没有向内网或 metadata 地址发起探测。

## 结论

当前实现能在应用层拒绝非 HTTPS、用户信息、query/fragment、本机和常见内网名称、禁止范围的 IP，以及 A/AAAA 结果中混入私网地址的端点。每次 AI 请求前重新检查，且禁止 HTTP 重定向。这些控制已经实现并有测试证据。

当前实现不能证明消除了恶意 DNS 重绑定。端点校验返回规范化 URL，随后 `fetch` 按主机名自行建立连接；校验取得的 IP 没有绑定到实际 socket。两次解析之间存在 TOCTOU 窗口，也不能从应用代码确认托管运行环境实际出站路由及代理策略。不得将“保存时验证过域名”或“请求前再次解析”表述为已完全隔离所有内网目标。

## 当前请求链路与保障

1. API 先验证账号；自定义配置只按认证用户读取。后台纪要/周报按实际记录 owner 读取配置。
2. `ai_settings.ts` 规范化地址，限制 HTTPS 和有效主机格式；拒绝 userinfo、控制字符、反斜杠、query/fragment。完整 `/responses` 或 `/chat/completions` 地址规范化为 base URL。
3. IP 字面量先经 URL 规范化再检查，防止十进制/十六进制 IPv4 和扩展 IPv6 写法绕过。拒绝 loopback、私网、link-local、CGNAT、组播，以及代码列出的文档/过渡地址范围。
4. 域名查询 A 和 AAAA；任意结果不符合公网策略就拒绝，空结果拒绝。解析服务异常明确返回可重试的 `AI_ENDPOINT_DNS`，不会使用默认服务。
5. `ai_provider.ts` 在每次请求前执行相同校验，包括环境配置的默认供应商。请求固定为 POST、`redirect:error`，密钥只放 Authorization 头。供应商失败不会切换到另一个地址或默认 AI。
6. 原始供应商错误体不读取、回显或记录；响应有大小、协议完成状态和 schema 校验。日志只保留安全错误码。

TLS 主机名校验仍由运行环境执行，没有代码关闭证书验证。HTTPS 能增加防护，但不是连接目标 IP 策略的替代品。当前规则也不是自动同步的完整 IANA 路由可达性数据库。

## 残余风险与部署验收要求

自定义服务地址由用户控制；攻击者控制的 DNS 可能在应用检查时返回公网 IP，在 fetch 自行解析时返回另一地址。应用没有检查最终连接 IP；DNS 缓存、重试和 HTTP 连接池行为也不能由当前测试替代证明。

若对任意自定义服务开放前需要消除这一窗口，部署层必须采用以下一种可验证方案：

- 出站网络策略阻断 IPv4/IPv6 内网、loopback、link-local、metadata 及其他不允许目标，并覆盖函数所有实际出口；或
- 受控出站代理负责解析、验证，并把连接固定到验证过的公网地址，同时保留正确 TLS SNI/主机名验证，禁止重定向到未验证目标。应用不能绕过该代理直接联网。

两种方案都需要运行态证据：公网供应商可用；双栈禁用目标不可达；重绑定、重定向和重试不能改变目的地策略。当前没有这些部署证据，本次没有擅自增加代理、修改防火墙或缩窄用户已授权的服务功能。仅增加域名白名单也不能单独解决恶意 DNS 重绑定。

## 验证证据与独立业务状态

- 当前全量 Deno 套件 76 passed / 0 failed，日志 `output/qa/custom-ai-edge-test.log`；三个 Edge 入口类型检查通过。
- `ai_settings_test.ts` 覆盖地址规范化、userinfo/query/fragment、私网 IPv4、映射/扩展 IPv6、混合公网/私网 A/AAAA、错误安全返回。
- `ai_settings_api_test.ts` 验证合成探测 `redirect:error`、本人隔离、不保存、错误脱敏；adapter 测试确认逐请求重新校验。此类模拟测试证明控制调用，不证明云端网络隔离。
- 协调者报告云端 Cron 最近三次 HTTP 均为 200 且没有 timeout；这证明近期调度触发成功，不证明供应商出站隔离。
- 协调者确认当前照片上传仍被 Storage Image Transform 的 `403 FeatureNotEnabled` 阻塞，项目所有者启用问题等待回复。这是图片转换服务能力阻塞，与 DNS 重绑定风险不同，不能合并为一个“AI 不可用”原因。

## 依据

2026-11-18 实际读取：

- Deno Fetch API / `Deno.CreateHttpClientOptions`：公开选项支持代理、自定义 CA、连接池等，未提供将本次已验证 DNS 地址固定到 fetch socket 的 resolver/lookup 选项。https://docs.deno.com/api/deno/fetch/#Deno.CreateHttpClientOptions
- OWASP SSRF Prevention Cheat Sheet：要求检查全部 A/AAAA、禁止重定向，并将实际连接绑定到已验证地址；二次未检查的 DNS 查询可绕过预先验证。https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html

先尝试网页工具未得到可读内容，随后通过 curl 读取上述官方页面；没有借此声称验证过 Supabase 云端 egress 策略。
