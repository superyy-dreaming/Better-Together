# Worker 交付状态

2026-11-18，本地代码与测试完成；尚未注入云服务凭据，不能视为线上验收完成。

## 独立审查后的修复

- 新增 cleanup 队列消费：删除前校验已删除media行与原图/分析图精确路径，Storage失败保留pending并自动重试，退避上限6小时、不因跨日或次数耗尽放弃隐私清理；成功仅在有效lease下更新done。异常路径不匹配标记任务需要人工检查，不删除其他对象。
- 已适配 `classification_pending`：用户编辑ALL摘要后仍继续分类，旧版本任务跳过；SQL负责保留用户摘要/字段。自动分类最终不可用时保留用户内容，memo unavailable/classification_pending false。
- AI/周报SQL返回lease_changed不会再被worker误记业务成功；按可恢复错误重排等待新租约。
- 运动数值仅显示在有来源字段中，不以“数字相同”放行摘要中不同单位的虚构距离。周报支持手填分钟/截图分钟，单条纪要的手填修正优先于原计时，避免重复累计；学习时长不计入运动。
- 修改后针对性检查：worker typecheck、5个修改文件lint、cleanup/job_state/AI/report共18个测试通过；其中新加6个测试。未重复运行未改动的其余模块测试，上一轮全量33通过。
- ALL批次备注不送入模型，防止其在公私混合照片中扩写到公开子组；单计划备注仍可使用。新增job_state隐私用例通过，3个状态测试全过。SQL须将未分配批次摘要保留在本人私有草稿，不能复制至各公开组。
- 最终复核：SQL现已将ALL备注/人工摘要与未分配字段保存为本人private batch draft，公开子组不含批次私人文字。hardening.sql含明确隐私断言，backend报告4组SQL集成通过。客户端模型已解析草稿，主线程接UI归属操作。

独立审查的其他模块发现与修复建议见 [review-findings.md](review-findings.md)，对应SQL与UI由其他责任模块处理。

## 已完成

- `media` JWT 验证、20MB JPEG/PNG 上传、原始 EXIF 与固定团队时区、运动截图完整日期 OCR、服务端感知哈希与数据库同队唯一索引、失败补偿。
- 生产使用 Supabase Storage Image Transform，私有原图保留，1600px 图用于解码/哈希/识别，避免 Edge 原尺寸解码超过内存。`storage` 不可用时显式错误；不会切换为不校验模式。
- `source=avatar` 上传分支：JWT 身份、5MB JPEG/PNG、512px JPEG、本人 UUID 路径、私有 avatars bucket、无日期/去重/打卡副作用。返回 `{id,path,source:'avatar',captured_at}`，客户端继续 `save_profile {avatar_url:path}`。临时头像原文件处理完成后清理。
- Responses strict JSON Schema、逐图归类/低信心 ALL、手选优先、混合分组重整、字段来源验证、运动数字保护、饮食热量区间；异步队列不撤销盖章，版本/租约保护用户修改。
- 周报只选择可验证 fact ID，最终事实句与数字由服务端渲染；SQL 事实版可先显示。
- APNs ES256、极光 REST 推送、按最新偏好发送、正常重试跳过已送设备、无效 APNs token清理、应用内通知独立可靠。
- `docs/ai.md` 运行、配置、故障处理与回滚；`functions/.env.example` 不含真实凭据。

## 验证

- `deno check`：api/media/worker 通过。
- `deno test --allow-env supabase/functions/_shared/`：**33 passed / 0 failed**，包括真实 JPEG/PNG 字节、原始 EXIF 偏移、图片格式与尺寸、哈希稳定性、混合信心归组、无来源数字剔除、strict/refusal、端点鉴权、chunked body 限额、APNs本地签名验证、推送错误分类、周报事实、头像存储补偿与转换请求格式。
- `deno lint`：worker 所有自有生产文件及测试通过。SQL 集成由 backend 代理独立执行。
- 本地 1600×1200 JPEG decode/hash约 95ms；12MP JPEG触发 jpeg-js 内存上限，已改架构使用 Storage 转换。该测量不是托管 Edge 运行验证。

## 真实 Storage 精确待验项

1. 项目为 Pro+ 且 Storage 设置启用 Image Transformations。代码 `download(path,{transform:{width,height,resize:'contain',format:'origin',quality:88}})` 已按官方 JS API 编写且类型检查通过，尚未对真实项目发请求。
2. JPEG/PNG 的 `format:'origin'` 响应需确认实际魔数仍可被解码，旋转 EXIF 是否由 imgproxy处理并移除/重设 orientation 需在真机四个方向样本验证。日期始终取原文件，不能取转换后的 EXIF。
3. 路径只有 `${userUUID}/${batchUUID}/${photoUUID}.jpg|png` 与 `${userUUID}/${avatarUUID}.jpg`，避免文件名转义问题；仍须真实 Storage 上传/下载/签名/删除 smoke。
4. HEIC/WebP 当前明确不接收。iOS/Android picker 导出的 JPEG 必须保留原拍摄 EXIF，缺 EXIF 时需原始相册 asset 创建时间；不能使用缓存文件的修改/创建时间。该客户端能力由原生代理继续处理。
5. 20MB multipart 在 Edge 256MB 中的峰值、9张顺序处理和并发用户需运行实际负载；原图先上传、转换失败补偿删除需注入失败验收。头像原始文件限5MB，保存的是512pxJPEG。
6. 删除原图与账号时同时删 analysis 派生图，Storage删除之后先前短时签名链接应返回不可用。现有签名链接在退出小队后可能仍有效至TTL到期（api图300秒、AI分析图180秒），需纳入隐私验收。
7. OpenAI模型权限、截图OCR、APNs/极光真机送达与点击没有真实服务验证，全部单测为mock。供应商接受推送后进程崩溃仍可能至少一次重复投递。

## 接口提示

上传头像不需要 batch_id；客户端可继续发送，服务端忽略。头像成功仅返回存储路径，不自动写个人资料，因此用户确认失败时旧头像保持不变；未被资料引用的新头像会在删除账号时清理。`save_profile` 后重新 bootstrap，所有本人头像使用统一URL刷新。
