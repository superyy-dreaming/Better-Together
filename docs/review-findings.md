# 后端 / Flutter 独立审查

基于 2026-11-18 当前实现静态端到端检查。未重复运行已通过测试；以下需要责任模块修复并增加针对性验证。

## 修复复核状态（14:25）

以下原始发现保留便于追溯，**不是当前未修复清单**。已复核最新实现：照片删除改为SQL原子cleanup队列且worker精确路径校验/自动重试；公开周报按当前team与分享期计数；逾期统一least(截止+30m,23:30)；重新归类先验字段并重算迟到/旧新逾期；暂停周wire输出bool；食物编辑器保留range对象；ALL编辑以classification_pending继续处理。

最后一个批次摘要隐私问题也已关闭：006把ALL原始note/编辑摘要存private batch_field_drafts.summary，bootstrap仅本人得到unassigned_summary，公开组仅使用对应照片的AI摘要；worker不会把ALL备注送入模型。hardening.sql包含“私密学习密码”不进队友snapshot、字段只保存一次与明确归属的断言，backend报告4组SQL测试通过。

客户端已完整展示unassigned_fields/unassigned_summary并提供assign_batch_fields操作，公开目标有明确发布提示，失败恢复和防重复已通过页面测试。真实云端故障恢复、Storage与推送验收仍依赖安全配置。

## P1：删除照片失败后没有可达的清理重试

位置：`supabase/functions/api/index.ts:75-82`、`202611180002_actions.sql:219-222`、`202611180004_bootstrap.sql:15`。

SQL 先写 `deleted_at`，Storage 删除失败才返回 `DELETE_RETRY`。Realtime/下一次 bootstrap 已过滤该照片，纪要页删除按钮消失，用户无法执行文案承诺的“再次删除”。原图和分析图会长期保留。此外 API 对查询 `analysis_path` 的数据库错误未检查，查询失败时会仅删原图并返回成功，分析图泄留。

建议：SQL 原子写持久清理任务（包含 original/analysis 两个 path）；worker 重试到实际存储删除完成，客户端可见“原图清理中”。至少必须在读取 analysis_path 出错时中止并返回可恢复错误。验收注入 Storage remove 与 analysis SELECT 错误，刷新页面后仍能自动完成清理。

## P1：更换小队后，周报汇总仍带入旧队历史

位置：`202611180007_reports.sql:1-29,112-113`。

`app.week_counts(user,week,true)` 只按公开计划/公开卡过滤，没有限定卡片 `team_id` 或当前 membership 的 `joined_at`；`team_week_counts` 对当前成员直接调用它。用户周三离开 A 小队加入 B，小队 B 的周报与用户新分享的个人周报公开快照会统计周一/周二 A 小队记录。`can_checkin` 已正确隐藏这些旧卡，但汇总绕过了退出后历史仅本人可见边界。

建议：公开版计数同时约束报告目标 team 与双方分享期。个人版保持完整；新队公开快照只含当前分享期的原队匹配卡片和应完成日期。验收用户 A→B、同队退出重入以及周中入队三种情形，旧记录/旧计划标题/完成计数均不进入新队快照。

## P1：截止 23:30 的计划不会产生当日逾期动态

位置：`202611180003_jobs.sql:119-123`；对照 `app/lib/domain/rules.dart:overdueSyncAt`。

SQL 只有 deadline >23:30 才封顶；deadline=23:30 则 due=次日00:00。扫描每日只遍历当地 today，午夜后改算新一天，因此昨天该动态永远不生成。23:01-23:29 的 SQL 结果也与客户端23:30封顶不同。

建议：统一为 `least(deadline+30m, 当日23:30)` 并补数据库23:00/23:15/23:30/23:50四点测试。也应明确任务停机跨日后的逾期补偿扫描口径。

## P1：已编辑纪要重新归类可能把精确运动热量带进饮食计划

位置：`202611180002_actions.sql:155-164`。

`reclassify` 只改 plan/visibility，保留 user_edited 字段且不按目标 category 调用 validate_fields。运动计划含 `{key:'calories',value:450,source:'manual'}` 后改成饮食计划，仍会显示单值450，不符合饮食必须估算区间。该 action 也没有重算 is_late；从早截止计划改到晚截止计划仍保留迟到，反向则可能错误增加连续记录。旧计划的 overdue_feed 也未重新开放。

建议：按目标 category 验证/规范字段，不能直接丢用户文本；重算目标当日截止与 is_late，并依据旧/新计划各自真实完成情况更新逾期记录。验收编辑后跨品类归类、前后截止不同、旧计划仍有/没有其他有效卡。

## P2：暂停周字段类型不一致，真实后端始终显示未暂停

位置：`202611180004_bootstrap.sql:5`、`app/lib/domain/models.dart:71`、`settings_page.dart:142`。

数据库返回 `paused_week` 为 ISO 日期或 null，而 Flutter `boolValue` 仅接受 bool。真实服务点击暂停后刷新开关仍 false，无法按界面撤销；Demo 写 bool 掩盖此问题。

建议 bootstrap 返回明确 `paused_week` 当前周布尔值，另给 `paused_week_start` 日期，或客户端解析日期并按小队固定时区比较当前周。补真实wire fixture测试。

## P2：饮食热量区间无法编辑或清空

位置：`app/lib/features/checkin/memo_editor.dart:35-47`、`202611180002_actions.sql:app.validate_fields`。

编辑器将所有修改过的字段统一转为 string/null。AI的 `calorie_range` 本来是对象，修改“450-650”会变成字符串并被后端拒绝，清空也会被拒绝。应提供上下限数字输入并保持 `{min,max,estimated:true}`；清空需删除字段。建议同样校验min>=0/max>min。

## P2：ALL 纪要编辑会永久阻断自动归类

位置：`202611180002_actions.sql:edit_memo`、`worker/index.ts:processAi`。

提交 ALL 后立即编辑摘要，会设 user_edited=true、memo_status=ready；worker跳过整项任务，因此照片不会再归类，小队也一直看不到private占位卡。需要将用户摘要优先与照片分类状态分开，AI仍可完成归类和其他未编辑字段；或者UI明确等待分类完成再改摘要。不能把“用户编辑优先”实现成“永不完成归类”。

## 已确认正确的边界

复核补充：修复ALL编辑时不要把批次用户摘要复制给每个public/private拆组。用户摘要可能描述私密计划，复制到公共运动组会泄露。保留一个private批次用户版本或明确匹配单组，公共子组只含其证据支持的内容。该问题已与backend同步，字段跨组复制还会造成时长重复计数。

- 迁移009的 `can_checkin/can_report/in_sharing_period` 对读取卡片/已分享个人周报正确限制退出及重新加入后的旧内容，bootstrap当前也调用这些函数。
- ALL提交初始private，识别后按目标计划visibility发布，避免异步前泄露私密计划照片。
- 个人周报公开快照不含私人 highlights/suggestion/evidence，原始 reports 表的RLS不向队友直接开放个人完整行。
- apply_ai_result 同时校验版本、user_edited和活跃lease；写回递增version，过期AI不会重复拆卡。
- 照片 Storage URL 是300秒短时凭证，退出队伍后已有URL在TTL内仍可使用；这属于当前设计的残留窗口，不能宣称即刻撤销。
