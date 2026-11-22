# 真实失败恢复探测脚本

ai_worker 请只编写 scripts/direct_ai_failure_smoke.py（以及脚本使用说明），不要执行真实请求，不读取.local文件实际内容，不改其他代码。root稍后执行。

脚本仅运行时读取.local/simulator.json（专用合成账号）、server.env（当前默认同域key/job secret）与cloud.env（service role）。用标准库urllib/PIL生成一张当前日EXIF、差异明显的合成图片，缩图≤1600，正常登录。记录旧ai_settings元信息，若账号已有自定义配置则停止，避免覆盖。临时用默认硅基流动域、同默认key、明确不存在模型保存该合成账号自定义配置。recognize应pending，media原图+analysis入库，submit_checkin ALL立即stamped。然后finally清除该脚本新增的自定义设置，恢复默认provider；触发worker并有界轮询bootstrap，验证保留盖章且纪要变ready。不能打印密钥/JWT/邮箱密码/照片dataurl/签名URL，异常输出脱敏error code。只创建合成测试记录，不清理用户数据。参考.local/direct_checkin_smoke.py的API结构可以读该代码，但不读它所引用的密钥文件。

检查真实接口字段，允许脚本在最终结果之后生成output/qa/direct-ai-failure-smoke-result.json，只含状态/计数/图片尺寸；不是伪造测试结果。该脚本与媒体入口修复并行，不依赖具体RPC。完成后将说明写docs/direct-ai-failure-smoke-status.md。
