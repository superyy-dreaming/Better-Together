# 直连 media 独立审查

日期：2026-11-18。审查 `supabase/functions/media/index.ts` 与 `_shared/direct_media_test.ts`。未修改入口或正式测试，未操作云端。现有 6 项测试通过，但下列故障路径可稳定复现，建议修复后部署。

后续状态：下列问题已通过迁移 015 与上传恢复实现修复，正式测试已覆盖正确行为；见 [direct-media-repair-status.md](direct-media-repair-status.md)。本文保留修复前证据，行号为当时版本。

## P1：数据库提交结果未知时会删除已被记录引用的原图

位置：`media/index.ts:213` 数据库 insert 与 `:283` 补偿 catch。

原图上传成功后，`media` insert 可能已经提交，而响应因网关 503 或网络断开丢失。代码只有响应成功才将 `registered=true`；当前 catch 因 `registered=false` 直接令 `mayRemoveObject=true` 并删除原图。此时数据库仍有 media 行，后续 worker/页面得到的原图却已被破坏。网络观测失败被当成“未提交”这一判断是根因。

修复要求：不能靠本次调用的布尔值证明没有数据库引用。未知写入结果需按 photo_id、owner、batch、原图和分析 hash 读取并核对实际提交状态；读失败时保留对象并记录待恢复状态，不做破坏性删除。清理需绑定确切对象/登记版本，避免与另一请求完成登记竞争。优先将 media 与 analysis 的数据库登记放到一个幂等事务 RPC。

## P1：media 与缓存分步提交可产生无法恢复的照片记录

位置：`media/index.ts:172` 已存在分支、`:258` 缓存 insert、`:287` 补偿 delete。

media 已提交但缓存写失败，若补偿 delete 也失败、进程中止，或者用户并发提交已令 `checkin_id` 非空，则 media 行保留而缓存缺失。再次上传相同 photo_id 时只检查缓存存在性，始终返回 `MEDIA_RECORD_UNAVAILABLE`，不会修复。用户被要求重试，但依赖恢复后仍无法完成。并发 submit 还能把这张缺少识别缓存的媒体盖章，worker 没有分析字节。

修复要求：media/cache 应在同一个数据库事务内登记，并对 photo_id 和完整字节身份绑定做幂等返回；或者引入持久化 incomplete 状态、拒绝 incomplete 的 submit，并允许同身份请求修复缓存。不能仅追加 retry 次数。缓存恢复不得延长原有效期，也不得覆盖已有 verified result。

## P2：Storage 已写入但响应丢失后，确定性路径永久冲突

位置：`media/index.ts:197` `upsert:false` 上传及错误分支。

Storage 实际成功但响应 503/连接断开时，`uploaded` 仍为 false，媒体未登记；下次相同上传仍指向同路径，Storage 返回对象已存在，代码统一映射为 503，再次重试无法退出。进程在 Storage 成功后、media 登记前中止也相同。

修复要求：对“对象已存在/上传结果未知”读取并验证该对象确为本次原图后继续登记，或使用持久化上传意图/恢复任务。不能盲目 upsert 覆盖可能属于已完成请求的对象，也不能把冲突永久包装为可重试服务故障。

## 本地复现与测试缺口

运行：`npx --yes deno test --allow-env --allow-read output/qa/direct-media-fault-repro.test.ts`。这是基于现有 fixture 的独立合成故障注入，共 9 项通过，包含原 6 项和 3 项“问题确实发生”的断言。最后 3 项通过表示复现成功，不能计为修复验收；修复后应将正式测试改为断言正确恢复并移除这个临时复现文件。

故障注入分别模拟：media 服务已提交但返回 503；cache 失败且补偿 delete 失败；Storage 已保存但首次返回 503、重试返回已存在。现有测试把 POST 错误都视作未提交，且 DELETE 必定成功，因此未覆盖这三个真实的非原子边界。

正确路径方面，当前入口服务端计算原图/缩图摘要与 pHash、验证 receipt 绑定、已完成上传的同身份重试不重复写 Storage、截图 pending 不虚构日期、普通相册缺 EXIF 拒绝，已有测试与实现一致。
