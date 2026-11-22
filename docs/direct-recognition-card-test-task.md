# 识别卡片验证子任务

请添加 app/test/recognition_card_test.dart，拥有仅此文件，不改生产代码，不运行 Flutter。现有 RecognitionCard 在 app/lib/features/checkin/recognition_card.dart，模型 DraftPhoto 在 checkin_draft.dart。验证 ready 真实摘要、置信度、来源，pending 明确状态无虚构运动数据，rejected 不显示成功，移除/重试可操作，以及 375px 和 768px 在 1.4x 字体浅深色无溢出。可用有效微小 PNG 字节，滚动/ensureVisible 再点按钮，按现有项目测试风格。不需要完整屏幕金图。dart analyze 可运行。完成写 docs/recognition-card-test-status.md。
