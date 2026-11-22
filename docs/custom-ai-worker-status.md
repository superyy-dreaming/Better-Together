# 自定义 AI 供应商接入结果

## 已实现

- `ai_provider.ts` 单独负责协议适配、供应商请求、响应边界和合成探测；`ai.ts` 保留分类/纪要业务规则，并重导出 `structuredResponse`、`testAiProvider`、`defaultAiProvider`，兼容已有调用。没有引入依赖。
- Responses 使用 `/responses`、`input_text/input_image`、`text.format.json_schema`。Chat Completions 使用 `/chat/completions`、`messages`、`image_url`、`response_format.json_schema`。均 strict、`store:false`；自定义供应商不强加 reasoning 参数。
- 默认服务尊重 `OPENAI_BASE_URL`、`OPENAI_PROTOCOL`、`OPENAI_MODEL` 与 `OPENAI_API_KEY`。地址留空才用官方 `/v1`，协议留空为 Responses；非法协议明确失败。未读取或输出 `.local/server.env`。
- 截图上传用认证用户 ID 加载配置；AI worker 用实际 checkin.owner，周报 worker 用 report.owner 加载配置，不信任客户端给的 user_id。每次请求重新校验端点并 `redirect:error`；任何自定义失败均不回退默认服务。
- 请求成功后也验证协议响应完成状态、拒绝标记和 JSON Schema。字段类型、required、additionalProperties、enum、数字边界、数组边界等当前 schema 使用项在本地验证，不信任供应商 strict 声明。保持逐图已知 ID、低置信度 ALL、手选优先、计时/OCR 来源、饮食区间及周报事实选择校验。
- 响应限制 1 MiB；非 JSON、畸形 envelope、截断、拒绝、HTTP 错误、网络错误均安全失败，原始错误体、第三方 refusal 文本和密钥不返回、不记录。HTTP 429/5xx 可在现有窗口重试，其余配置错误不做无意义重试。
- `testAiProvider(provider)` 返回 `{ok:true,message:string}`，只发送嵌入的 32×32 合成红色 PNG，校验图片可见、主色与严格 JSON，无用户照片或资料。供 API 当前输入测试和 root 安全实测调用。

## 实际验证

- `npx --yes deno test --allow-env --allow-read supabase/functions/_shared`：74 passed / 0 failed（本轮全量）。修复旧 `ai_test.ts` 的测试 fixture：用公网 IP 合成 provider，测试不依赖外部 DNS，生产 DNS 校验保持启用。
- 随后新增供应商 401 不撤销盖章的 worker 测试；`ai_worker_provider_test.ts` 共 3 项通过。其余 74 项代码未变，当前合计 75 项。
- `deno check`：ai.ts、media/index.ts、worker/index.ts 通过。
- `deno lint`：adapter、业务 AI、报告、media、worker 与 3 份新增测试通过。

新增 18 项测试覆盖两协议的精确 URL/模型/密钥/图片/strict request、schema 错误、拒绝、截断、合成图片探测、HTTP 不回退及脱敏、逐请求地址校验、默认 BASE_URL/PROTOCOL、截图/纪要/周报路由。包含真实 handleMedia/handleWorker 路径及 Supabase fetch 模拟：加密保存的本人密钥被解密用于目标供应商，最终结果仍带任务租约 CAS；供应商错误仅使纪要 unavailable，未修改打卡 status。

## 官方依据

已用 OpenAI Docs skill，并实际读取以下官方页面，确认两协议图片 content 与 strict JSON 格式、refusal/incomplete 和业务校验要求：

- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
- https://developers.openai.com/api/docs/guides/images-vision

## 验证边界

本轮全部外部请求由合成 fetch 模拟，没有使用真实用户图片、真实供应商凭据、远端部署或 Flutter 构建。真实服务能力由 root 在安全环境运行合成探测确认。

端点检查沿用 backend 的 `validateAiEndpoint`。它拒绝内网解析并禁止重定向；DNS 检查与 fetch 连接之间仍存在 DNS 重绑定竞态，不能宣称应用层已完全消除，需要部署网络出站策略或受控代理作最终隔离，详见 `custom-ai-backend-status.md`。

回滚：函数回退此前版本即可，新增 013 密文表保留，不删除用户配置；重新部署前按 runbook 先迁移再部署函数，避免新代码访问尚不存在的表。
