# Recognition repository 子任务

阅读 direct-recognition-contract.md。只拥有 app/lib/domain/models.dart、app/lib/data/app_repository.dart、app/lib/data/supabase_repository.dart、app/lib/data/demo_repository.dart 和新建 repository 测试；不改 checkin_page、photo_preparation、app_controller。

1. 新 PhotoRecognitionRequest(bytes 为 analysis JPEG, photoId, batchId, source, originalSha256, planId可空) 和 PhotoRecognition(photoId,status,planId?,confidence?,summary,fields,screenshotDate?,error?,receipt?)；提供 isReady/isPending/isRejected。pending factory 或 const constructor允许使用 pending 状态。字段名按上述 Dart camelCase。请求 bool/类型显式，status服务响应未知格式应报错不冒充ready。
2. PhotoUpload保留现有字段，新增 analysisBytes Uint8List?、photoId String?、recognitionReceipt String?。avatar流程兼容。
3. AppRepository.recognize(PhotoRecognitionRequest)新增；Supabase经 functions/v1/recognize multipart file=image/jpeg，添加photo_id,batch_id,source,original_sha256,可选plan_id，不走api动作避免128KB上限。在 repository 可注入 http.Client 方便可验证multipart测试。get/post鉴权不日志key。
4. upload multipart增加 analysis(image/jpeg)、photo_id、recognition_receipt，原file不改变。客户端识别超时/网络/HTTP5xx转换PhotoRecognition.pending，HTTP4xx证据/格式/鉴权保持AppException（不能当AI失败）。recognized status rejected保留。
5. Demo.recognize返回明确pending“演示模式不运行AI...”，不保存/上传原图、不伪造ready。原upload兼容新字段，不应自动拒绝所有pending照片。截图演示仍明确不运行OCR。
6. 必要 wire/multipart测试；不要运行Flutter，root串行构建。可dart analyze。完成写docs/recognition-repository-status.md并停止修改。

主client_data负责压缩和Checkin UI，按上述接口对接。通讯消息可能被隐藏，以本文件为准。
