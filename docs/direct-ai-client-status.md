# 先识别后归档客户端交接

实现已完成，`dart analyze lib test` 全客户端与测试静态分析通过。按并行约定尚未运行 Flutter 测试或构建，请主任务串行执行下列命令；不能把静态分析记为运行态通过。

```sh
bash scripts/flutter.sh test test/photo_preparation_test.dart test/checkin_draft_test.dart test/recognition_repository_test.dart test/recognition_card_test.dart --no-pub
```

## 最终行为

- 选择照片后保留 picker 导出的原始字节及 EXIF。后台 isolate 生成 JPEG，长边 <=1600、<=2MB，烘焙方向、剥离 EXIF/GPS/ICC，原始 SHA256 与压缩图一起 POST `/functions/v1/recognize`。这一阶段无 Storage/media 写入。
- 每图展示真实摘要、计划建议、置信度、截图日期、字段来源。低置信度提醒核对标签。待识别不编造纪要。用户可移除、重试、选择本次记录标签。
- ALL 严格多数只是建议；预览识别请求不传手工 plan_id，让建议独立于之后的标签调整。提交时只在用户选了计划时发 plan_id；未选计划完全省略，交给后端最终多数。
- 压缩仍进行时不能提交；压缩完成、AI 尚未返回时有显式“先按 ALL 盖章”入口。操作将未完成图片记为 pending 并清除本次显式计划，后台继续识别。版本标记阻止迟到响应覆盖已归档内容。日期/证据明确 rejected 或 HTTP4xx 不参与这个降级。
- 用户确认后才将原图、analysis、photo_id、不透明 receipt 上传 media，再调用 submit_checkin。失败图片逐图可见；部分拒绝需确认剔除，部分上传失败需确认采用其余图片。已成功上传项不会重复上传。
- 草稿绑定创建时的账号，切换账号立即清除照片；每个异步阶段与归档循环均检查身份，避免余下原图以新账号发送。
- 保留纸面/印章视觉、全宽照片与滚动布局、安全区、大字体和系统控件；页面在准备、识别、pending、rejected、成功待确认等状态给出明确说明。

## 修改范围与测试

客户端：domain/models、AppRepository/Supabase/Demo 实现、photo_preparation、CheckinDraft、CheckinPage、RecognitionCard；AppController 新增一行 recognize 转发。

新增 28 项测试（尚未执行）：photo_preparation 2 项；CheckinDraft 8 项；repository 9 项；RecognitionCard 9 项（含 375/768px、1.4x 字号、浅深色）。详细数据层交接在 recognition-repository-status.md，卡片测试交接在 recognition-card-test-status.md。

补充：Demo 的 recognize 明确返回 pending，不伪造 AI；演示截图原有 OCR 不可用拒绝仍保留。真实服务的截图 pending 放行与后台 OCR 由新的 media/worker 契约处理。请 root 用真实合成图片验证非演示链路。
