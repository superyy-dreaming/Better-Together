# 识别 pending 可观测性

交付日期：2026-11-18。仅修改 `supabase/functions/recognize/index.ts`、`_shared/recognize_endpoint_test.ts` 与本说明；未部署。

识别 catch 的 pending 分支新增一条 `console.error` JSON 事件，固定字段为 `event=recognition_pending`、`photo_id`、`code`。code 必须是代码中明确列出的内部 ServiceError 错误码；非 ServiceError 或不在白名单的值统一记录 `UNEXPECTED`。不记录 message、stack、供应商返回正文、服务地址、模型、账号、token、密钥或图片内容。

客户端继续收到相同的 generic pending 与无 receipt，可按 ALL 盖章；正常 ready/rejected 不产生 pending 日志。没有调整超时、模型、客户端或后台处理行为。

## 错误定位

- `AI_HTTP_ERROR`：供应商 HTTP 请求被拒绝或失败，仍不读取/输出其正文。
- `AI_INVALID_SCHEMA`、`AI_INVALID_JSON`、`AI_INVALID_RESPONSE`、`AI_INVALID_RESULT`：响应解析、结构或业务校验失败。
- `AI_SETTINGS_KEY`、`AI_SETTINGS_ENCRYPTION`、`AI_SETTINGS_UNAVAILABLE`、`AI_CONFIGURATION_INVALID`、`CONFIGURATION_REQUIRED`：配置/密钥读取与服务配置问题。
- `AI_ENDPOINT_DNS`：端点 DNS 检查失败。
- `AI_UNAVAILABLE`：当前 adapter 对连接异常与超时的共同分类。本改动没有把它进一步断言为超时；需结合供应商/运行日志继续诊断。
- `SCREENSHOT_DATE_PENDING`：截图日期未核实。
- `UNEXPECTED`：未知异常，仅记录固定码，不泄露原始异常内容。

## 验证

recognize 入口测试 9 项通过，其中新增 schema、密钥解密配置、未知异常和 timeout 模拟。pending 测试捕获日志并断言恰好一条事件、恰好三个允许字段、正确内部错误码；供应商回显、密钥、token、URL、data URL、message 和 stack 不得出现。原 ready/rejected/跨计划/无鉴权回归保持通过。

完整 Edge 测试本轮 **115 项通过，0 失败**，日志 `output/qa/recognition-observability-test.log`。recognize Deno check 通过，日志 `output/qa/recognition-observability-check.log`。

root 部署 recognize 后可按 `recognition_pending` 与具体 photo_id 检查真实错误码。当前结果只证明本地合成 mock 与静态检查通过，不代表已经定位真实供应商错误。
