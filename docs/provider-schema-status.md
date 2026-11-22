# 兼容供应商结构化输出修复

## 根因证据

root 的真实供应商检查显示：请求 HTTP 成功、`finish_reason=stop`，响应可解析为 JSON，但纪要对象缺少 `photo_ids`、`fields` 并含未声明字段；另一次返回 `AI_INVALID_JSON`。因此通路和凭据可用，问题位于供应商对结构化输出契约的执行，不能靠放宽解析或调整超时解决。

## 已修改

- `supabase/functions/_shared/ai_provider.ts`：保留两种协议原有的 strict JSON Schema 参数，同时把原业务指令、仅输出有效 JSON 的约束及完整 Schema 放进 Responses `instructions` 或 Chat Completions `system` message。
- 明确要求所有 required 字段齐全、禁止额外字段、遵守类型/枚举/范围、仅使用 Schema 允许的 null，空数组保留为 `[]`，不输出 Markdown/解释/注释/尾逗号，也不编造事实。
- 原有 JSON 解析、本地 Schema 校验、业务来源校验及失败后的 pending 语义保持不变。不修补缺失字段、不接受代码围栏、不改模型、超时或 token 限制。
- `supabase/functions/_shared/ai_provider_test.ts`：覆盖两个协议的完整 Schema 注入，验证原 instructions 保留；使用真实 memoSchema 回归缺字段、额外字段、null、Markdown JSON、尾随文字与合法结果原样通过。
- 保留此前 `recognition_pending` 的安全错误码可观测性；不输出供应商正文、图片、私有 URL 或凭据。

## 验证

- provider 专项：16 项通过。
- 全部 Edge 测试：117 passed / 0 failed。
- Deno check：api、media、recognize、worker 四入口均通过。
- 验证日志：`output/qa/provider-schema-test.log`、`output/qa/provider-schema-check.log`。

## 交接边界

本轮未部署、未执行真实供应商调用，未修改客户端和数据库。Schema 同时传入参数与系统指令有助于兼容端点理解完整契约，但不保证第三方一定遵循；本地校验仍为信任边界，格式不合格仍进入 pending，不会伪装成识别成功。

root 可重新部署 api、recognize、worker，使共享 adapter 更新生效，再使用合成照片验证真实供应商识别、确认盖章及失败恢复。部署后的真实结果必须另行记录，不能用本地测试结果代替。回滚时仅还原这次 adapter 的 Schema 指令拼接及对应测试，不回滚先前隐私、来源校验或日志脱敏修复。
