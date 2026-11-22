# 客户端收尾任务

请 client_data 负责以下文件的实现，避开 root UI：
1. DemoRepository 支持 avatar 上传（免日期、保存本地图片），interact_report、unregister_device，补有意义测试。演示仍不假装AI和云服务。
2. 生成明确品牌的文字应用图标（BT 字母/纸面收据印章方向，深绿背景与米纸文字，禁用Flutter默认图标），通过脚本生成iOS各尺寸和Android mipmap PNG，脚本保留于scripts。无需生成式AI，采用系统字体排版，避免手绘UI图标。
3. 审查 app/lib/data/app_controller.dart 登录/退出后旧状态泄露、realtime权限问题与头像失效问题。
4. 不运行Flutter build，root正串行跑模拟器。可以dart analyze指定文件，提交结果到 docs/client-final-status.md。

worker审查补充（root UI需要）：后端Checkin新增classification_pending boolean，编辑ALL后memo_status可能ready但classification_pending=true，需继续轮询与展示归类中；自动归类失败会memo unavailable，用户摘要保留。photos新增cleanup_status pending时url为空，显示清理中而不是空图错误。Demo wire需要同步新字段语义，否则真实服务与Demo不同。
# 当前最高优先事项：实际完成 Memo 草稿 UI

数据层已完成，但 app/lib/features/checkin/memo_page.dart 尚未使用 unassignedFields/unassignedSummary/classificationPending。请实际编辑页面，而非仅提供接入建议。

你拥有 memo_page.dart 和必要的新组件/独立测试。要求：

1. 本人记录存在 unassignedFields 或 unassignedSummary 时显示仅本人私有草稿、摘要和字段，并提示未计入周报。
2. 列本人同 batch 的可用卡供选择；调用 assign_batch_fields {checkin_id: 原卡, target_checkin_id: 目标卡}。
3. 目标计划 visibility=team 时明确提示会把这份内容发布到小队可见记录，由明确的确认按钮提交；防重复，显示失败恢复。
4. memoStatus=pending 或 classificationPending=true 时继续显示/更新归类进度，不能因人工编辑ready停止。
5. 新增页面测试：只有摘要也可归属、不同批卡不列出、公开目标提示、提交一次、失败保留草稿。

最新契约见 docs/backend-coordination.md。做完写 docs/client-final-status.md。不要改 app.dart/notifications/history/reports，不要跑原生 build。

