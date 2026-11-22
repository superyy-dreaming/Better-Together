# 后端实现与验证

## 已实现

12 份按序 SQL 迁移，JWT 鉴权 API、私有 Storage 访问、RLS、成员隔离与退出后的历史保护、计划下周生效和规则历史、每人 3 个计划、每批 9 图、服务端哈希唯一、幂等提交即盖章、独立 AI/报告/推送/清理队列及租约 CAS、逐图 ALL 拆分、人工编辑优先、质疑过半与连续记录冻结、每人每天 2 次质疑、补卡每月 2 次、次日中午边界、逾期与戳聚合、个人/计划/小队连续记录、周报事实计数与 6 种称号、分享双动作、报告点赞评论、只分享公开计划的周报投影、可采纳的频率建议、通知偏好、账户删除及媒体清理。

Realtime publication 迁移包括客户端订阅表及 report_interactions。`supabase/deploy/schedule.sql` 提供每分钟调用 worker 的 pg_cron + pg_net + Vault 配置，不包含任何真实 secret，也没有执行到云端。

## 已实际验证

- `bash supabase/tests/run.sh`：4 组 SQL 集成测试通过。使用全新 PostgreSQL 17 临时集群，模拟 Supabase 的 auth.uid/roles/storage schema；每组事务回滚，集群自动停止和清理。包含 5 人队 3 票、3 人队 2 票、未过半不变、冻结不倒扣、RLS/私密照片、ALL 原子分组及人工编辑后继续分类、租约错配、报告公开投影、退出重入/换队、6 种称号、23:00/23:15/23:30/23:50封顶、重新归类的字段来源/迟到/逾期同步、照片持久清理与设备注销。
- `npx --yes deno check supabase/functions/api/index.ts supabase/functions/media/index.ts supabase/functions/worker/index.ts`：通过。
- `npx --yes deno test --allow-env supabase/functions/_shared/`：39 项通过，0 失败（含媒体/AI/报告/推送/头像/持久清理/人工编辑状态实现的单元测试；详见 ai.md）。
- 账号删除先持久标记并阻止新的业务写入和 Storage/media 入库，撤销 worker 租约。按 500 条分页读取媒体路径并分批删除原图和 AI 缩图；递归清理 evidence/avatars 本人前缀（含孤立上传）。数据库级删除级联与删除中上传拦截已测，真实 Storage 删除、错误恢复与并发上传需要云端验证。
- 单张照片删除原子入 cleanup 队列，原图和分析图都在任务中，重复点击不创建重复任务。清理中图只向本人返回空 URL 与 cleanup_status=pending，刷新仍能看状态；成功凭租约标记 done。Storage 故障由 worker 重试，不依赖用户再找到按钮。
- ALL 自动分类拆成多组时，已编辑字段不会复制到每组。字段暂存一份本人私有 draft，由 assign_batch_fields 归入同批次的一张卡；未归属不计周报。ALL 原始说明和人工摘要也保存在私有 draft 的 unassigned_summary，公开子卡仅用对应照片摘要。SQL 已验证含私密文本的草稿对其他成员完全不可读、归属一次后仅选中卡显示。选择小队公开卡是用户明确发布该草稿的动作。
- 新增并通过未调用 edit_memo 的 ALL 提交说明回归测试：即使仅归成一组且 user_edited=false，原始 note 仍保存在本人私有草稿，队友 bootstrap 不含该文字；本人明确选择公开卡归属后才可被队友读取。完整 4 组 SQL 套件再次通过。

## 尚未验证 / 实际边界

- 用户尚未安全注入真实配置。Supabase Auth、SMTP、Apple、Storage、Realtime、OpenAI、APNs/极光、Cron、移动设备端到端都没有真实联调通过证据。
- SQL 测试不包含 Supabase Gateway/Storage 服务，不能替代真实多账号越权测试。退出后不再发新签名 URL，已发出的签名 URL 最长仍有效 5 分钟。
- 周报建议仅由完成/应完成天数提出减少下周频率，不推断漏打原因；若要求“时段冲突/漏提醒/难度”分类建议，仍需收集原因。
- Cron 以一分钟粒度检查；周报支持错过周日后补生成最近一周。错过整天的逾期任务还没有历史补扫。
- 全队共同连续记录使用当前成员的当前分享期间。成员变动后的历史团队连续口径没有单独冻结快照。
- 「次日 12:00 重打」按质疑达到阈值当天的小队时区计算，避免对历史卡发起质疑后得到已经过去的截止时间；重打仍归回原卡日期。
- 账户删除在 Storage 与 Auth 间没有跨服务事务：部分失败保留删除中状态并返回明确重试信息，不报告成功；实际多请求竞态仍需 Supabase 联调。
- 移动端发布签名、商店后台与生产隐私合规不在后端本地验证结果中。

部署和回滚见 [backend-runbook.md](backend-runbook.md)，接口见 [contract.md](contract.md)。未执行 commit、push、远端迁移或部署。
