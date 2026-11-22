# 上传恢复修复交付

2026-11-18：`direct-media-review.md` 三项问题已修复并通过本地回归。未部署、未读真实配置、未改客户端或 worker。

## 实现

- 追加迁移 `202611180015_media_registration.sql`，014 保持原有语义。`register_direct_media(p_media jsonb,p_analysis jsonb)` 只有 service_role 可执行，在一个事务内写 media 与 media_analysis；缓存约束失败时整笔回滚。
- RPC 以账号及 photo_id 的事务锁串行处理重复/冲突请求。已有 ID 必须匹配 owner、batch、team、日期、路径、source、pHash、原图 SHA256 和分析 SHA256；不同内容返回 PT409，不能覆盖已有记录。重新校验当前账号和小队。已删除记录不能恢复，已过当日返回 PT410。
- 已完成的重试返回原结果，不重复写原图、不覆盖 verified result、不延长缓存 TTL。兼容旧的 media 存在/cache 缺失：同身份可原子补回，created_at/24h 到期时间锚定原 media，超过恢复期限明确拒绝。
- media 原图 upload 仍为 `upsert:false`。返回错误或抛异常时读取确切私有原对象，核对大小和服务器 SHA256；同字节继续登记，异字节返回冲突，读取不可用返回可重试状态。此处没有 Transform、没有模型调用。
- 已删除旧补偿逻辑。Storage 或数据库提交结果未知时保留原图，同一 photo_id 的请求在依赖恢复后可继续；任何观测失败都不能直接删除对象。公开日志只记录 `media_archive_recovery_pending` / `media_archive_registration_pending`、media_id 与错误代码，不记录图片/密钥/URL/纪要正文。

## 验证

- `npx --yes deno test --allow-env --allow-read supabase/functions/_shared/direct_media_test.ts`：13 项通过。覆盖原有上传/日期/receipt、事务失败后的重试、提交响应丢失、Storage 响应丢失、读取暂时不可用、旧缓存补回、并发同 ID 同字节、并发同 ID 异字节、分析图冲突。
- `PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH bash supabase/tests/run.sh`：15 份迁移、7 组 SQL 和独立双连接并发测试全部通过。RPC 权限、缓存失败时原子回滚、缓存结果/TTL不被覆盖、原有时间锚定、跨账号/内容冲突/过期/删除保护均有断言。真正的两个 PostgreSQL 连接验证同身份均成功且只有一份记录、异身份只有一个成功且另一个 PT409。
- api、recognize、media、worker 四入口 Deno check 通过。media 源码和测试完成 Deno fmt。
- 日志：`output/qa/direct-media-edge-test.log`、`direct-media-edge-check.log`、`direct-media-database-test.log`。旧的“问题复现通过”临时文件 `direct-media-fault-repro.test.ts` 已删除，不再混作验收。

## 部署与剩余边界

应先应用 014、015，再部署新版 media 与其他直连入口。原有云端成功记录不能替代这次部署/真实打卡 smoke。015 不新增客户端接口或可见字段，不改变 worker RPC。

为了避免删掉另一个请求已引用的原图，当前上传入口在登记失败、重复图或未知状态时保留该确切私有对象；同身份可重试恢复。无法登记的孤儿对象可能继续占空间，日志提供媒体标识供核查。**本轮没有新增自动孤儿回收器**；运维清理必须先阻止该上传身份继续登记，并证明没有 media 引用，不能按目录或仅根据一次失败响应删除。账号删除沿既有私有目录清理流程。

回滚通过追加迁移或回退兼容 015 的函数，保留队列、原图和缓存；不要回退到已知“写失败即删除原图”的实现。长期处理规则见 [agent-media-lifecycle.md](agent-media-lifecycle.md)。
