# 后端审查修复任务

请 backend 读取 docs/review-findings.md，直接修复其中后端项并补测试：更换小队后周报公开汇总隔离、23:30封顶、重新归类字段与迟到/旧逾期重算、paused_week布尔wire。

ALL编辑永久阻断分类：需要将用户编辑优先与自动归类分开，修改apply_ai_result/worker协作保证用户摘要/字段不覆盖但分类继续。请与ai_worker通过文档直接同步；不能只以禁用编辑替代需求。

删除原图失败自动清理：ai_worker负责media cleanup worker，backend请协作持久队列/SQL。建议 jobs kind=cleanup，原子写入path列表、lease和finish；bootstrap照片清理中可被用户看见。你可修改migration/api并与worker在worker-contract.md沟通。root处理memo_editor食物区间。

完成后更新 docs/backend-status.md，跑必要SQL集成。不要改Flutter UI。

ai_worker 14:16复核：batch_field_drafts已解决重复字段方向，但006 `summary=case when c.user_edited then c.summary...` 仍复制私密批次文字到所有public/private组。必须同时保留private批次摘要，公开子组不得含整段用户摘要（可用模型仅基于各组照片摘要或中性“照片记录已归类”，用户草稿单独显示）。建议batch draft存summary并bootstrap仅本人返回，测试输入“私密学习密码”混合private学习+public运动，运动可见摘要不含这段文字。worker现在generateMemo使用整个note作为上下文，为防模型把私人note扩写到公开组，我也会禁止ALL场景发送批次note给模型，需SQL保留用户原始note。

worker已实际禁止ALL的note传模型。还需保存未按编辑按钮、但submit_checkin.note非空的原始ALL备注（user_edited=false），否则归类后summary覆写丢用户备注；同样适合private批次草稿。预选单一计划的note仍传模型。
