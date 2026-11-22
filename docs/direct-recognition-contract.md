# 直连识别实施契约

用户在 2026-11-18 明确调整链路：选图 → 客户端压缩至长边不超过 1600 → Edge 代理逐图识别 → 展示与改标签 → 确认后私有存档原图并盖章。识别异常按 ALL 盖章、当天后台补识别，不依赖 Storage Image Transform。沿用账号自定义 AI，密钥仅由后端持有。

## 接口

`POST /functions/v1/recognize`，JWT，multipart：`file` 为 <=1600 JPEG（上限 2 MB），`photo_id` UUID、`batch_id` UUID、`source`、`original_sha256`（原图字节 SHA256）、可选 `plan_id`。服务器读取本人计划、时区及 AI 配置，逐图分类/OCR/摘要。返回 `{data:{photo_id,status:'ready'|'pending'|'rejected',plan_id,confidence,summary,fields,screenshot_date,error,receipt}}`。仅 ready/rejected 包含由服务器 HMAC 签名的 receipt；pending 可无 receipt。错误文案不得泄露供应商内容。响应只含已校验结构化数据，不写 Storage。用户照片仅到本人配置的服务。

receipt 使用 JOB_SECRET HMAC-SHA256，含 user_id/batch_id/photo_id/original_sha256/analysis_sha256/source/expires_at/result/screenshot_date；24h 有效。共享模块提供签发与校验，校验绑定实际上传的原图和缩图 SHA256、账号和批次。外部不能伪造 AI 结果。

`POST /functions/v1/media` 保留原有 original `file`；新增 `analysis` JPEG <=1600/2MB、`photo_id`、`recognition_receipt`（可选）。客户端选好图不调用 media；确认盖章时才上传。无 receipt 或 pending 允许上传并盖章，后台识别。原图仍逐张校验日期/服务端计算缩图 pHash/全队去重。截图已识别出过期日期必须拒绝；截图 AI 暂不可用则标记日期待核实，允许 ALL，后台补 OCR，不虚构日期。原图只在私有 evidence 桶保存；不存 analysis_path，不调用 Storage Transform。

## 数据及后台

新增迁移 014：`public.media_analysis` 以 media_id FK cascade 为主键，user_id FK cascade，`data_url` text（临时压缩图），`result` jsonb（单图 AiResult），`screenshot_date` text nullable，`recognition_status` text，`expires_at`（24h），created_at。RLS on；revoke public/anon/authenticated；service_role CRUD。不进入 bootstrap/Realtime/日志。数据 URL 最长 3 MB。正文缓存只为当天重试，超时清空 data_url；保留校验后的文本结果，原图删除/账号删除 cascade。

worker 读取 media_analysis，成功的单图结果复用，缺失结果逐张经 Edge AI adapter 重试，传 data URL（禁止从 Storage 签名 URL 识别）。ALL 按严格多数（超过总张数一半）的非空计划归类；平票/无多数/任一图处理失败时保留 ALL 待确认，不强行归类。用户指定计划优先。聚合摘要和字段按同一目标生成一个组，保持隐私和来源校验。失败不撤盖章；首次有可用结果可直接 ready。保留版本/租约控制。

## 分工

- root：media 原图归档改造、集成/部署/模拟器、端到端脚本和收口。
- client_data：Flutter PhotoRecognition 模型、压缩与摘要字节、repository 识别/上传接口、打卡先识别/结果确认/改标签/失败 ALL、客户端相关测试。不改其他后端。
- ai_worker：recognize 入口和共享 direct_recognition.ts（含 receipt）、worker 逐图与多数聚合/临时缓存清理、相应测试。可改 ai.ts 增加导出，不改 media 入口和 migrations。
- custom_ai_backend：014 media_analysis 迁移、SQL 测试、检查提交的 ALL/人工计划与 worker 应用兼容性、文档/配置移除 Image Transform 必需限制。不改 worker/recognize/media/client。

## 验收

真实合成图片先识别且零 Storage 写入；确认后原图私有存档、即盖章；worker 使用返回内容完成纪要。模拟 AI 故障仍 ALL 盖章、后台按同一路径补识别；多图多数与平票、过期照片、跨账号 receipt、篡改摘要/原图、重复照片、私有访问、清理均验证。

## 补充边界

media 同时将服务端计算的原图 SHA256 写入 metadata.original_sha256；014 添加相同队伍作用域的部分唯一索引，防止同一原图搭配伪造缩图绕过去重。pHash 仍在服务器从压缩图像像素计算，不采信客户端的 hash 字段。超大原图不在 Edge 全量解码；第三方改造客户端可能伪造原图与缩图的对应关系，此边界应记录，不能声称密码学证明两图像素一致。

截图识别明确读到旧日期时拒绝；模型不可用或无法读取日期则 pending，后端原图 metadata.date_evidence 标为 screenshot_ocr_pending，不伪造“已核实日期”。后续 OCR 明确旧日期保留盖章历史并提示凭证待重交，不编造可用纪要。其余相册照片始终以原图 EXIF 验证，旧照片不得通过 AI 故障降级。
