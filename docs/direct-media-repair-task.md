# 上传恢复修复任务

请 custom_ai_backend 立即继续并实现 docs/direct-media-review.md 的三项问题，而非只审查。你独占 supabase/functions/media/index.ts、_shared/direct_media_test.ts、追加015迁移与相应SQL测试。014已经dryrun但尚未云部署。建议通过service-only幂等事务RPC原子写media与analysis，严格身份绑定；Storage upload成功但响应丢失/存在时，读取对象核对实际SHA再继续，不盲目upsert；任何未知状态不得删除可能被其他请求引用的原图。优先保留可恢复对象，避免不安全补偿。仅在证明没有引用和无竞争时才清理，不可把观测失败认定未提交。让重试有明确退出路径。

参考现有contract和review。追加015，不改014历史语义；修复后运行media tests/SQL suite和四入口check，更新direct-media-repair-status.md。不得读真实.local密钥、不得部署云端、不得改app。删除output/qa/direct-media-fault-repro.test.ts临时复现，正式测试覆盖正确恢复。并发重复ID/不同byte冲突也覆盖。
