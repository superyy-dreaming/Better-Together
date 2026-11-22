# Flutter 逐图识别接口

本文件供客户端并行实现使用，模型位于 `app/lib/domain/models.dart`。

- `PhotoRecognitionRequest({required Uint8List analysisBytes, required String photoId, required String batchId, required String source, required String originalSha256, String? planId})`
- `PhotoRecognition({required String photoId, required String status, String? planId, double? confidence, String summary = '', List<MemoField> fields = const [], String? screenshotDate, String? error, String? receipt})`；getter `isReady`、`isPending`、`isRejected`。
- `AppRepository.recognize(PhotoRecognitionRequest photo)` 和 `AppController.recognize(...)` 返回 `Future<PhotoRecognition>`。
- `PhotoUpload` 保留原字段并增加 `Uint8List? analysisBytes`、`String? photoId`、`String? recognitionReceipt`。头像可不提供；记录上传提供全部分析字节及 photoId，receipt 有则原样提供。

识别只 POST `/functions/v1/recognize` multipart，不上传 Storage。网络中断、超时、HTTP 5xx 结果返回 `pending`，`error` 为明确可先 ALL 盖章的安全文案，不带 receipt。HTTP 4xx（包括 400 证据拒绝、401/403 鉴权、408/429）直接抛 `AppException`，保留服务端错误 code/message；页面必须视为阻止该图提交，不能降级。成功响应 `status=rejected` 同样不可提交。服务器 `status=pending` 原样保留安全 error。响应的 error 可以为 `{code,message}`，模型将其拆成 `error` 和 `errorCode`。

返回 photo_id 必须与请求一致，status/置信度/字段类型必须有效；结构异常返回 pending 并显示识别结果暂不可用，不编造 ready。若响应已明确 `status=rejected`，即使结构不完整也抛出阻止提交的 `AppException`，避免被当成 AI 故障放行。Demo 返回明确 pending、提示不执行 AI；无存储写入、无假摘要。

`SupabaseAppRepository` 构造器增加可选 `http.Client? httpClient`，仅用于识别/媒体上传测试与连接管理；注入 client 生命周期归调用方，默认 client 在 dispose 时关闭。
