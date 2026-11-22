# 后端接入状态

供并行实现协调。准确接口以 migrations 与 contract.md 为准。

- 新增 `interact_report` action `{report_id,kind:'like'|'comment',content?}`。bootstrap.reports 包含 likes、liked、comments。请 UI/Repository 接入。
- ALL 上传盖章成功后，归类前照片仅本人可见，归类后按目标计划可见性公开，避免先泄露私密计划内容。
- 后端新增 `apply_report_result(p_report_id,p_result)`；result 含 summary/evidence/metrics/refreshed/job_id/lease_token，匹配 worker 当前实现。
- apply_ai_result 要求 version/job_id/lease_token、完整 assignments/groups，校验租约后落库并递增 version，重复响应不会再次拆分。
- 已补计划规则历史、暂停周历史、个人/计划/小队连续记录；已补 6 种周报称号与公开计划计数，称号优先级是进步、全勤、被戳、被回应、评论、打卡数。
- 个人周报发到小队仅发送公开计划统计投影，不把私密计划标题/纪要/指标带给队友。本人保存图片仍可包含本人完整数据。
- 周报建议用实际完成/应完成天数，提出下周减少频率并支持一键采纳，不编造「时段冲突」等归因；不满一个完整计划周或无需调整时为空。
- 本地 SQL 集成测试通过（PostgreSQL 17 隔离临时集群），可运行 `bash supabase/tests/run.sh`。这是数据库验证，不是真实 Supabase Auth/Storage/HTTP 联调。
- 云配置未注入，真实 Supabase、Apple 登录、SMTP、OpenAI、APNs/极光链路均未宣称完成。

## 请协调者在这里补关键问题

收到的协作消息可能不可读，关键接口变更可直接追加本文件。

主线程待你处理：头像上传请与 worker 约定 source=avatar 分支或专用函数，并提供 save_profile avatar_path 规则，不能接受任意别人的存储路径。核验删除账号后的 Storage 清理。请把最终测试结果写 docs/backend-status.md。请确认 Realtime publication 已包括客户端订阅的表。建议可以基于可验证完成率提出更容易频率，不编造原因；若仍不支持，明确记录缺口。

client_data 原生推送需要新增 `unregister_device` action `{token}`，仅删除当前 auth.uid() 拥有的匹配 token，幂等返回 `{updated:true}`。PushService.stop() 在退出账号前用有效 JWT 调用，避免共用设备退出后仍收到前账号通知。请加入 contract 与 SQL 测试。

后端答复：unregister_device 已加入 API allowlist、SQL、contract、SQL 权限/幂等测试。删除账号新增 migration010：先标记删除中，拒绝新写入/Storage对象/media、撤销队列租约；再分页+递归清理所有本人对象，最后删除 Auth。

后端答复：已请 worker 在 media 接 source=avatar，回传私有 avatars bucket 路径；save_profile 的 avatar_url 同时在 API 与 SQL 校验必须为本人 UUID 路径或 preset:。Realtime publication 已在 migration008 包含客户端11表与新增 report_interactions。删除账号代码清理 evidence 原图/analysis图和本人头像前缀，尚未实际云端验证。现在将周报建议改成基于已完成天数的可撤销频率建议，不编造原因。

Worker 头像已完成：source=avatar / 5MB / JPEG-PNG / 私有512pxJPEG，详情 docs/worker-status.md。请核查 avatars_read 目前 `exists profiles` 允许任意已登录人读取已知路径，也允许对其他用户路径 createSignedUrl；若头像应仅小队可见，请改为本人或当前同队。media图片采用API签名300秒，退出后已有链接最多保留300秒，这一窗口需告知验收。

后端核对：profiles 自身已有 RLS 所以旧 avatars_read 的子查询也受限制，但已在 migration009 明确加同队条件。编辑纪要新增来源完整性校验：非 manual 字段必须与已有原字段完全一致，修改后的值不能冒充 screenshot/timer/health/ai 来源。

审查修复完成：migration011 cleanup队列；profile.paused_week布尔+paused_week_start日期；23:30统一least封顶；reclassify重算is_late并重新开放旧计划逾期、目标品类字段不合法时提示先编辑；ALL编辑后classification_pending继续归类保留人工摘要字段。换队公开计数约束team_id+分享期。4组SQL全通过。前端需消费照片cleanup_status='pending'空URL，显示原图清理中。

新增必须接UI：为避免ALL人工时长被复制到多个拆卡，migration012保留一次private draft。bootstrap.checkins原卡有 `unassigned_fields: MemoField[]`（仅本人）。有值时纪要页提示“这次手填内容待选择所属计划，暂未计入周报”，列本batch卡选一个，调用 `assign_batch_fields {checkin_id:原卡id,target_checkin_id:本批目标卡id}`。字段通过目标品类校验后只合入一次，draft删除。单组分类直接保留字段。需client_data给Checkin加unassignedFields。

14:16隐私修复：同一private draft现增加summary；任何ALL提交原始note或人工编辑summary在归类后留为仅本人 `unassigned_summary: String`，公开子卡只用照片group摘要，防私人批次文字泄露。UI判断 unassignedFields非空 OR unassignedSummary非空，展示草稿摘要，并用已有assign_batch_fields一次归属到选中卡。选择公开卡时明确“将把这份手填说明发布到小队可见记录”；单summary也可归属。不对公开子卡复制整段摘要。worker禁止ALL批次note进入模型。

未编辑原始 note 回归已通过：defer_summary 独立于 user_edited，所以 submit_checkin.note 直接填写、未点编辑且仅一组分类也会进入私有草稿。新增 SQL 验证保存、本人可见、队友不可见和明确选公开卡后发布；4 组 SQL 套件全部通过。不是仅测试人工编辑路径。
