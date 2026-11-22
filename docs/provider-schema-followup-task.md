# 真实供应商结构输出修复

ai_worker 请立即继续。目前真实默认硅基流动识别多次pending，root本机截取的脱敏结果证明：HTTP成功，finish_reason=stop，JSON可解析，但 memoSchema violations 为 $.groups[0].photo_ids:missing、$.groups[0].fields:missing、$.groups[0]:extra。另一次直接AI_INVALID_JSON。模拟器首次图可成功，说明调用通路与凭据有效，但兼容端response_format并不稳定强制完整schema。

请修改共享ai_provider structuredResponse：在原strict JSON response_format之外，把要求仅输出JSON且精确匹配schema的说明和完整schema一并放在system instructions内（Responses同理），让兼容端点即使未强制schema也能看到字段契约。仍保留本地严格验证与pending失败语义，不降低schema、不补造缺失字段、不简单放宽解析、不调timeout/token参数。必要新增受控格式诊断区分JSON/schema，但不要输出供应商正文/图片。新增测试验证请求确实包含schema且仍拒绝不符合结果。运行全Edge测试/check。root等你完成后重新部署recognize/worker/api并真实验证。不要执行真实供应商调用、不改app/数据库。

已有recognition-observability更改保留。交接写docs/provider-schema-status.md。
