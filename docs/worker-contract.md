# Media / worker 集成契约

## 审查修复协作（已对齐）

`jobs.kind=cleanup` 已实现：delete_photo 同事务设 `media.deleted_at` 并 `cleanup_status='pending'`，payload `{media_id,user_id,bucket:'evidence',paths:[original,analysis]}`。worker使用现有 claim_jobs/finish_job，Storage remove幂等，依赖失败无限重排（间隔上限6h），不改变盖章。成功后调用 `complete_media_cleanup(p_media_id,p_job_id,p_lease_token)`，SQL检查活跃cleanup租约且payload.media_id吻合，更新 cleanup_status='done'。失败保留pending。bootstrap给本人已删除但pending图返回 `{id,url:'',source,captured_at,cleanup_status:'pending'}`；其他用户不返回已删除图。API已停止同步Storage删除，返回 `{deleted:true,cleanup_status:'pending'}`；重复请求不另建任务。任务路径与media不符则标dead/needs_attention，拒绝不明归属的删除。

ALL编辑：worker已取消user_edited整项跳过，仍要求job.payload.version与当前version一致。edit_memo对尚未完成归类的记录重新排入带新version任务。classification_pending独立于memo_status，用户摘要可ready而归类仍在进行。

Worker已适配实际 `classification_pending` boolean。仅当user_edited且classification_pending=false才跳过。永久错误将memo_status=unavailable、classification_pending=false，但不清summary/fields。UI若user_edited应显示“自动归类暂不可用，你的纪要已保留”，不要声称用户纪要丢失。

Backend已决定：多组拆分时人工字段保留为private batch_field_drafts，只有本人bootstrap看到原卡unassigned_fields；各组fields空，不计周报。ALL原始note/人工summary也保留private draft的summary，bootstrap本人unassigned_summary，公开子卡用对应照片的group摘要。用户以assign_batch_fields选择同batch的一张卡后一次性转入该卡并删除draft。仅一组且字段适配目标品类时直接保留字段，但ALL批次摘要仍需明确归属。worker必须禁止ALL批次note进入模型，防组摘要间接泄露。

本文件在修改媒体、队列或 SQL worker 接口时读取。部署配置与错误恢复见 [ai.md](ai.md)。

## 媒体

- 私有 bucket `evidence`。`media` 保存 `id,user_id,team_id,batch_id,path,analysis_path,source,captured_at,local_date,phash,metadata,checkin_id,deleted_at`。
- `media` endpoint 使用真实用户 JWT 取得身份，service role 写入经过服务端验证的行。`reserve_photo` 不得向 authenticated 授权，因为日期/哈希不能由调用者伪造。
- `guard_media_batch` 对 batch ID 加事务锁，每批最多 9 张未删除图。`evidence_team_hash` 索引保证同队哈希唯一。单人按 user ID 去重。
- 原文件保留；生产通过 Storage Image Transform 生成 1600px 缩图，再服务端解码、算哈希和 AI 分析。必须配置 Pro+ 图片转换；`local` 模式仅用于 <=4MP 合成样本。
- `source=avatar` 不需要 batch_id，最多 5MB JPEG/PNG，私有 avatars bucket 中保存 `${user.id}/${uuid}.jpg` 的 512px 归一化图片，返回 `{id,path,source:'avatar',captured_at}`。客户端调用 save_profile `{avatar_url:path}`，不能提交外部 URL。头像不写 media/checkin、不验日期、不去重。

## 任务

`jobs`：`kind=ai/report/cleanup`，`status=queued/processing/done/dead`，`attempts,available_at,lease_until,lease_token,deadline_at,payload`。`push_outbox` 独立处理设备通知，状态和租约语义相同。

- `claim_jobs(p_kind,p_limit)` / `claim_push(p_limit)` 原子领取并生成新 lease token。
- `finish_job(p_id,p_lease_token,p_error?,p_retry_at?)` / `finish_push(...)` 只有同一处理租约能完成；重试变 queued，无法继续变 dead。
- `schedule_due()` 幂等生成逾期、通知和报告。HTTP worker 接受 `ai/push/report/cleanup/schedule/all`，需要 `x-job-secret`。
- 推送发送前重读偏好与聚合文案。成功设备 token 的 SHA-256 指纹写入 `payload.delivered`，并对 lease token 做 CAS；重试跳过已记录设备。外部接受后、落库前崩溃仍可能产生重复，属于至少一次投递。

## AI 写回

Backend review fix: checkins now has classification_pending boolean, set true for ALL until first classification. edit_memo increments version and enqueues a new ai job while classification_pending. Worker must select this column and skip user_edited only when !classification_pending. apply_ai_result allows edited+pending classification, preserves user summary/fields in every group, sets classification_pending=false. Ordinary edited classified memos still skip AI. Please update worker accordingly.

Backend accepts worker proposed cleanup contract at top of this file: `media_id`, `complete_media_cleanup(p_media_id,p_job_id,p_lease_token)` and per-photo cleanup_status. Ignore older photo_id/finish_photo_cleanup wording. Function marks media done under active lease; worker then calls finish_job as usual.

`apply_ai_result(p_checkin_id,p_result)` 只允许 service role。输入包含：

```text
version, job_id, lease_token,
assignments: [{photo_id,plan_id,confidence,reason}],
groups: [{plan_id,photo_ids,summary,fields}]
```

SQL 同时检查活跃任务租约、checkin 版本与待处理状态，所有照片恰好一次且归组一致。user_edited且classification_pending=true时只继续分类并保留用户内容。分组事务性拆卡，写回后递增 version。字段 `duration_seconds` 的来源必须合法。AI 饮食热量由 worker 转为 `{min,max,estimated:true,unit:'kcal'}`。

低信心归 ALL，手选计划优先；调整后的相同计划分组会合并，混合信心拆组时只保留可确认的通用摘要。计时不能分配给两个运动计划，存在歧义时留空待用户确认。

AI 任务以创建该任务的团队当地日期为重试窗口，最多 8 次。24 小时内用户主动重新分类可以产生新的任务；旧版本不能覆盖新版本。

## 周报写回

`apply_report_result(p_report_id,p_result)` 输入 `{summary,evidence,metrics,refreshed,job_id,lease_token}`。SQL 比较 metrics/refreshed 快照以及活跃任务租约；只更新个人 summary/evidence，不修改小队公开快照。

模型仅返回事实 ID；文本/数字由服务端模板从数据库计数与有来源纪要字段生成，evidence 保存依据。用户刷新周报需生成新的 report job。AI 不可用时保留 SQL 事实版，最多 16 次、72 小时内重试。
