# 后端立即实施任务

请阅读 direct-recognition-contract.md（含补充边界）并实施你的 custom_ai_backend 分工：014 media_analysis 表、RLS/service_role约束、原图SHA256队伍作用域唯一索引、SQL集成测试。用户明确不再使用 Storage Transform，更新 scripts/check_config.py 及测试、docs/setup.md、docs/backend-runbook.md、docs/validation.md，不要将旧部署事实描述为已完成新链路。

不要改 worker/recognize/media/client。完成写 docs/direct-ai-backend-status.md。请确认直接写状态文件，跨agent消息可能是空正文。运行本地SQL/配置测试可自行继续，但不部署云端、不读取secret。
