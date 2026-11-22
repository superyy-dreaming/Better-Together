# 客户端立即实施任务

请完整阅读同目录 direct-recognition-contract.md。用户已明确改为先压缩图片经 Edge 代理识别，确认后再上传原图私有存档；AI 失败按 ALL 盖章。你拥有 app/ 所有代码与测试修改；root 不改客户端。该契约取代先前消息中的 mode=preview API，不实现旧消息所说的 mode=preview。

实现现有 image 包后台 isolate 压缩 JPEG <=1600、<=2MB，原始 bytes 保留存档并 SHA256。AppRepository 增加 recognize 方法（避免 api 128KB限额），调用 functions/v1/recognize multipart。新增 PhotoRecognition 模型。服务回执 receipt 原样传回 media 新增字段 recognition_receipt；media 原图 file、压缩图 analysis、photo_id、source、batch_id、captured_at。逐图展示summary/confidence/plan建议、可手动选择标签。ALL严格多数建议，仅用户人工修改才发送显式plan_id，其余后端worker最终多数。准备完可确认盖章，timeout/AI错误仍允许ALL；HTTP400旧图等证据拒绝不能误当AI失败。页面不要上传Storage直到用户确认。

做压缩/字段传递/失败仍可提交的必要测试。保留平台风格、滚动/大字体。不要跑Flutter以免与root构建冲突，完成把摘要及测试命令写 docs/direct-ai-client-status.md。

识别期间允许用户选择“先按 ALL 盖章”，不能为了等待网络锁住盖章入口。逐张最多等待合理服务超时（现有adapter超时可对齐）；后返回的结果必须检查页面仍mounted/照片仍存在/尚未进入提交，不能覆盖用户手动标签。任何未完成照片按pending提交缓存待后台重试。
