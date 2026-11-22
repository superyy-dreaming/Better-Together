# 逐图识别数据层交接

状态：实现完成，可由主任务串行运行 Flutter 测试。

- `PhotoRecognitionRequest` 使用 `analysisBytes` 构造参数，兼有 `bytes` getter；正式接口见 `direct-recognition-models.md`。
- `PhotoRecognition` 保留分类、置信度、纪要字段、截图日期、错误 code/message 与不透明 receipt。未知状态、非法置信度、错误类型和缺失成功回执不会冒充 ready。
- `recognize` 只将分析 JPEG 以 JWT multipart 发送到 `/functions/v1/recognize`，不存档原图，不调用 Storage。网络、超时及 HTTP 5xx 为显式 pending；所有 HTTP 4xx 保持阻止提交。明确 rejected 即使字段残缺或 photo_id 不符，也保持阻止提交。
- `upload` 保留原图字节，另附 analysis JPEG、photo_id 与原样 receipt；头像不带这些字段仍兼容。响应到达时校验当前账号，防止旧账号结果进入新草稿。
- Demo 只返回明确的 pending，不伪造识别结果，不写入证据。没有增加依赖。
- 新增 `app/test/recognition_repository_test.dart`，覆盖 multipart 边界、原图保留、头像兼容、故障与拒绝区别、账号切换和 Demo 无写入。中文模拟响应显式使用 JSON 编码。

验证：对 models、AppRepository、Supabase/Demo repositories 和新增测试执行 `dart analyze`，结果 `No issues found!`。按并行任务约定未运行 Flutter 测试或构建。

主任务待运行：在仓库根目录执行 `bash scripts/flutter.sh test test/recognition_repository_test.dart --no-pub`。wrapper 会自动进入 `app` 目录。

编辑范围：本子任务拥有 models、repository 接口及两种实现、新增 repository 测试和本交接文件。`app_controller.dart` 曾补入一行 recognize 转发；已交由客户端主任务维护，不再修改。
