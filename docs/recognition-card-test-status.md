# 识别卡片 UI 测试交接

状态：新增 `app/test/recognition_card_test.dart`，未修改生产代码。

共 9 项 widget 测试：

- Ready 显示服务端摘要、计划建议、置信度、截图日期与字段来源；缺失运动消耗保持“未记录”。
- 低置信度保留原结果并显示人工核对提示。
- Pending 明确 AI 故障、原图尚未上传和后续整理语义，不渲染运动时长、消耗、置信度或成功摘要。
- Rejected 保持不可提交状态，不显示成功纪要和 ALL 放行文案。
- 375px 窄屏、1.4 倍字体下滚动后可点击重试与移除，回调各触发一次。
- 375px、768px 与浅/深色组成 4 项布局测试；每项覆盖 preparing、recognizing、ready、pending、rejected 五种状态，使用 1.4 倍字体及长摘要/计划名，检查框架异常及所有文本的横向边界。

使用 `image` 包生成有效 2×2 PNG，仅作为测试图片，不依赖网络或图库权限。

验证：`dart analyze test/recognition_card_test.dart` 返回 `No issues found!`。按分工约定未运行 Flutter 测试或构建，因此上述运行态断言仍待主任务执行验证。

主任务命令：仓库根目录运行 `bash scripts/flutter.sh test test/recognition_card_test.dart --no-pub`。
