# 直连识别 Worker 交付记录

日期：2026-11-18。实现及针对性验证已完成，尚未由本任务部署或做真实供应商验证。

## 修改范围

- 新增 `supabase/functions/recognize/index.ts`：JWT 鉴权后逐图识别，读取本人计划/固定小队时区/自定义 AI；返回 ready、pending 或 rejected；不写 Storage 或数据库。
- 新增 `_shared/direct_recognition.ts`：JPEG 边界校验、服务端 pHash、SHA256、HMAC 收据、截图 OCR/单图纪要、严格多数及字段来源聚合。
- 修改 `worker/index.ts`：只使用 `media_analysis` 的临时 data URL 或已验证文本结果，不签发 Storage URL 识别；成功缓存、部分成功可见、未完成图接续、过期字节清理。
- `ai.ts` 的 `PlanChoice` 增加可选 visibility，服务查询包含实际可见性。
- 新增 direct_recognition / recognize_endpoint / direct_worker 测试，并更新原 ai_worker_provider 测试为 data URL 链路。

没有修改 media 入口、迁移或客户端；没有部署、读取真实密钥或输出用户照片。

## 共享导出契约

文件：`supabase/functions/_shared/direct_recognition.ts`。

- `sha256(bytes)`：小写十六进制 SHA256。
- `validateAnalysisImage(bytes)`：真实 JPEG、≤2 MiB、宽高均 ≤1600，在解码前检查头部尺寸，解码后计算 pHash；返回 `{bytes,dataUrl,sha256,phash,width,height}`。
- `ReceiptBinding`：`user_id/batch_id/photo_id/original_sha256/analysis_sha256/source`。
- `issueReceipt(binding,outcome,secret?,now?)`：JOB_SECRET HMAC-SHA256，24 小时；outcome 为 `status:'ready'|'rejected',result:AiResult|null,screenshot_date,error`。
- `verifyReceipt(token,binding,secret?,now?)`：验证签名、有效期与全部绑定，失败 `RECOGNITION_RECEIPT_INVALID`。media 必须传实际原图和缩图的 SHA256；不能相信表单声明值。
- `recognizePhoto(input,provider?,fetcher?)`：只接受 JPEG data URL；单图分类与纪要。截图 OCR 读到非当天日期时抛 `ScreenshotDateMismatch`，包含实际 `screenshot_date`；缺失日期可重试。
- `aggregatePhotoResults(items,plans,selectedPlanId,timerSeconds)`：一个最终分组。ALL 仅在所有图片有结果且某个非空计划超过总张数一半时归类；否则保持 ALL。人工计划优先，计时只追加一次，来源重新校验。具体计划的摘要/字段不混入少数其它计划内容；ALL 内容由后端保持 private。

签名绑定证明收据未被改动及上传字节匹配客户端声明的原图摘要，不声称服务端已从全尺寸原图重算压缩图。服务端另有原图 SHA256 去重和缩图 pHash。

## SQL 接口及隐私

worker 发送 `partial` 和 `privacy_required`；旧提案 `privacy_restricted` 不再使用。

- 至少一图成功时可 apply partial，纪要 ready、classification_pending=true、version 保留，然后继续任务；全部失败不 apply。全部完成后正常版本递增。
- ALL 存在私人计划、无法归类或缺失结果时 `privacy_required=true`。即使多数是 team 计划，也不得扩大少数照片的可见性。人工计划是用户显式选择，沿用所选计划可见性。
- 末次失败只更新仍为 pending 的纪要，不覆盖已经展示的 partial ready 内容，也不改盖章状态。
- partial 的 AI 摘要不会被下一次任务误当作用户原话发给供应商。014 迁移对原始 note/draft 的保留负责。
- 调用 service-only `clear_expired_media_analysis()`；清空到期 data_url，保留验证后的文本，删除归档时按数据库规则清缓存。

## 生命周期

现有租约两分钟。九张图顺序处理可能越过租约或 Edge 生命周期，因此每次租约只处理一张尚未完成的图，最多 OCR + 纪要两次请求；其它已成功图直接复用。`AI_BATCH_REMAINING` 是进度接续，下一次 Cron 可继续，不按供应商错误退避；真实错误在当天窗口内有界重试，AI 总领取次数上限 32 为九张图接续预留次数。报告与推送重试规则未改动。

## 验证

`output/qa/direct-recognition-worker-test.log`：37 项通过，包含本次新增 21 项、更新的 provider worker 3 项及既有 AI/状态机回归。`output/qa/direct-recognition-worker-check.log`：recognize/worker Deno check 通过。

新增测试验证：确认前零 Storage/数据库写入、本人 provider、鉴权、跨账号/批次/原图/缩图/来源、HMAC 篡改与到期、JPEG 字节/大小/长边、截图固定时区/旧日期/未知日期、严格多数/平票/缺失/人工计划、字段来源、私人少数保护、partial 恢复、缓存复用、到期、后台拒绝和九张图逐租约接续。

该记录只证明本地代码与合成 mock 验证；真实媒体登记、云端存档、完整盖章闭环与模拟器由 root 集成验收。

## 完整 Edge 回归补验

旧 `ai_media_provider_test.ts` 已迁移至 handleRecognize 两项真实入口 mock 测试：当天截图先 OCR 再纪要、旧截图在 OCR 后拒绝；均验证本人加密 provider、小队固定时区、截图字段来源、签名结果及确认前零 Storage/数据库写入。

完整 `npx --yes deno test --allow-env --allow-read supabase/functions/_shared/` 通过：104 项、0 失败。日志：`output/qa/direct-recognition-edge-test.log`。api/media/recognize/worker 四入口 Deno check 退出码 0，日志 `output/qa/direct-recognition-edge-check.log`；Deno 缓存命中时该日志可能为空。这轮只修改旧测试与本记录，生产代码没有新增改动。
