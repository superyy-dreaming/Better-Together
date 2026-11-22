# 当前需实施：个人周报长图验证

拥有 app/lib/features/reports/reports_page.dart，可抽取 report_receipt.dart/report_export.dart，新增独立测试。不要改其他模块，不要跑原生构建。

当前 on-screen RepaintBoundary.toImage 需证实报告长于视口时仍导出完整、不截断底部。仅本人个人报告可导出，不含队友数据。检查分享异常恢复与重复触发，保留现有 UI。

请实际实现必要修复，测试生成 PNG 宽高/底部内容完整，并把样本 PNG 保存 output/qa/report-export.png 供主线程视觉检查。测试可用合成个人报告，不要冒充真实云端数据。写 docs/report-export-status.md 的改动和实际验证结果。
