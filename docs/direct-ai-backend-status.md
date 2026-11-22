> 历史记录：本文中的后端持钥、代理和服务器 AI 任务已由设备 BYOK 架构替代。不得据此恢复旧链路。当前实现见 [ai.md](ai.md) 和 [byok-rollout.md](byok-rollout.md)。

# 直连识别数据库与配置交付状态

更新时间：2026-11-18。本分工已完成，本地验证通过；未部署云端、未读取真实安全配置。集成与部署由主任务执行。当前契约以 [direct-recognition-contract.md](direct-recognition-contract.md) 为准。

## 可供部署

- 迁移 `202611180014_direct_recognition.sql` 已完成，可按 013 后顺序应用。新增 `media_analysis`，只有 service_role 可读写，不进入 bootstrap 或 Realtime。缓存归属、创建时间、24 小时有效期不可更改，JPEG data URL 最大 3 MiB；ready 必须有包含 assignments/groups 的结果。
- `clear_expired_media_analysis()` 仅服务端可执行，返回清空数量；到期只清 data_url，保留文本结果。软删除原图立即删缓存，硬删照片或账号也级联清理。清空过期字节不受账号删除状态阻挡。
- `metadata.original_sha256` 必须为 64 字符小写十六进制。同队原图哈希唯一索引 `evidence_team_original_sha256` 阻止同原图配不同缩图重复提交；无 hash 的旧行兼容。冲突为 PostgreSQL 23505，media 可沿用重复照片处理。
- `apply_ai_result` 保留既有 lease/version/owner/字段来源保护。含缓存的新批次强制单一聚合组；ALL 未归类保持 private 与 classification_pending，不因 AI 失败撤章。显式所选计划不能被 AI 改写。
- 接受 `partial:true`：memo_status=ready、classification_pending=true、version 不变，便于同 job/lease 后续重试；ALL 的 partial 不能提前指定计划。完整结果才递增版本。原始用户 note 只在首次写入私密 draft，后续 AI 结果不覆盖它。
- 接受 `privacy_required:true`：自动 ALL 批次归类后保持私有。数据库另检查缓存结果里的私密计划来源，即使漏传 flag，也不会因公开计划占多数而公开私密照片。用户显式选择计划优先；null ALL 始终 private。

## 已执行验证

- `PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH bash supabase/tests/run.sh`：PostgreSQL 17 独立临时集群，14 份迁移、6 组 SQL 测试全部通过。结果日志在 `output/qa/direct-recognition-database-test.log`。
- 新 SQL 组覆盖：RLS/权限、bootstrap/Realtime 隔离、跨账号与同队原图去重、输入/有效期约束、ALL 即时盖章、单组多数、平票隐私、人工标签、partial 同租约重试、原 note 保留、私密少数来源、软删/硬删/账号删除与到期清理幂等。
- `python3 -B -m unittest discover -s scripts -p check_config_test.py -v`：6 项通过。只使用临时合成配置；配置检查不再要求 MEDIA_IMAGE_MODE 或 Storage Image Transform。

## 文档与集成边界

配置示例、setup/runbook/validation/AI 运行说明已改为「客户端压缩 → Edge 识别 → 用户确认 → 原图私有归档与盖章」。历史 13 迁移/3 函数及旧 AI 探测只保留为历史证据，不表示新链路已部署或云端通过。

worker 需使用上述字段名和 RPC；数据 URL 到期或旧媒体缺少缓存时必须明确处理，不允许回退 Storage 签名 URL 进行识别。原图/缩图哈希绑定及服务端 pHash 可以防替换和重复，但不能证明上传缩图与原图像素一致。截图 pending 的日期语义、过期 OCR 后用户提示、跨账号 receipt、真实模型与客户端 smoke 由整合验收覆盖。

后续独立 media 审查发现的未知提交结果与补偿恢复问题已修复。新增 015 原子登记迁移、13 项 media 测试、SQL 和真实双连接并发测试通过，部署前需一起应用 015，详见 [direct-media-repair-status.md](direct-media-repair-status.md)。

回滚应回退兼容当前 RPC 的函数或追加修复迁移，保留原图、队列和 AI 密文；不 drop/reset 数据库，不重新启用旧 Transform 上传链路。
