# 设备 BYOK 识别架构

本文件描述迁移 `202611210020` 及以后版本。性能优化仍按 [逐步证据](ai-byok-progress.md) 实施，尚未验收的优化不能视为已上线。

## 调用与凭证边界

用户在设置中填写 HTTPS 接口地址、API Key 和模型。应用只使用用户自己的 Chat Completions 服务，图片通过 base64 image_url 发送。首次预填硅基流动地址与模型仅是示例；没有预装 Key、默认服务或备用模型。清除后保持空白。

配置按本机和当前账号隔离，使用 flutter_secure_storage。iOS Keychain 禁止同步并采用 this-device-only；Android 使用 Keystore 保护的加密存储并排除备份。已存 Key 不回显、不进入 Supabase、任务元数据、代码或日志。连接测试使用合成图，只检测当前表单，不自动保存。严格 JSON Schema 不可用时，仅通过连接测试确认的 JSON Object 模式可用，所有结果仍接受同一结构校验。

App 直接连接所填站点。Supabase 负责鉴权、计划与日期上下文、私有原图归档、去重、业务规则和结果保存，不调用 AI、不保管 AI Key。旧 recognize 返回升级／待补状态；旧 AI 配置接口拒绝读写；worker 的 ai/report 分支不领取或执行任务。

## 照片生命周期

1. 选图后读取原始 EXIF，再离线压缩和移除分析图元数据。原图内容不改写。
2. App 获取本人的计划、固定小队时区与日期上下文，直连服务识别；确认前不将照片上传 Storage。
3. 结果逐图校验，AI 建议不覆盖手选。80% 门槛、严格过半、全部成功才自动归类；平票、无多数、任一 pending 留 ALL。
4. 用户确认后才通过 media 归档私有原图，服务端独立检查日期、归属及重复；AI 不可用或日期未知不等于已知不合格。明确旧日期仍剔除。
5. submit_checkin 幂等保存并盖章。逐图 BYOK 数据与归属分开保存；后续结果通过 save_byok_photo，检查所有者、记录版本、照片 revision、当前小队 scope 和请求幂等键。
6. App 应用级队列负责补识别。离开页面不结束任务；系统挂起时持久化身份与重试状态，回到前台重新鉴权后恢复。账号／配置变更取消旧调用。自动重试仍限当天，过期只能主动补生成。

队列只保留账号、照片 ID、版本、状态和重试时间，不保留 Key、图片或供应商正文。权限撤销、删除照片、记录版本变化会停止旧结果写入。保存响应未确认不能等价为保存失败，不能因此盲删已归档对象。

截图必须读到完整日期，缺失则待核实，不猜今天／昨天。运动时长、距离与消耗只能采用截图或已有设备来源；不新增手填运动数值。历史 manual 来源保留，但不计入有来源运动统计。学习只记录可见内容；饮食热量仅为注明估算的区间。逐图摘要保留 1～3 句事实，不评价、不提供医疗建议。

当前第 2 步维持旧性能参数：1600 像素、无多图并发上限、截图 OCR 与纪要两调用、6500 输出预算、单调用 45 秒／单图 60 秒。并发、尺寸、单调用和参数优化必须各自复测后再切换。

## 周报

服务器继续生成规则统计与事实摘要。本人打开周报时，App 用当前 BYOK 配置选择服务器提供的 fact IDs；服务端重新渲染文本与数字，不能由模型增添事实。结果按周报版本保存复用，定稿或数据变化使旧缓存失效。未配置或失败仍显示完整规则版。共享快照不受私人 AI 摘要影响。

## 归档、通知与清理

所有照片和头像使用私有桶及签名 URL，全项目禁止 Supabase Storage Image Transform；本地 Flutter 界面 transform 不属于此限制。缩略图、APNs／极光推送、schedule 与 cleanup 仍由服务端执行。

删除原图先由事务标记 deleted_at 和清理状态，立即撤销新的读取权限，再由 worker 校验确切路径和租约执行删除。依赖失败进入可恢复状态，不能删除其他媒体或盲清用户目录。已发短期签名 URL 要等 TTL 或对象实际删除失效。

## 验证、部署与回滚

```sh
bash scripts/flutter.sh analyze
bash scripts/flutter.sh test
npx --yes deno check supabase/functions/api/index.ts supabase/functions/recognize/index.ts supabase/functions/media/index.ts supabase/functions/worker/index.ts
npx --yes deno test --allow-env --allow-read supabase/functions/_shared/
bash supabase/tests/run.sh
python3 -B -m unittest discover -s scripts -p check_config_test.py -v
```

部署与密钥清理按 [BYOK runbook](byok-rollout.md)。只允许回滚至无后端 AI Key 的兼容版本；必要时关闭 AI、保留正常打卡。不得恢复旧代理、密文表或旧云端 Key。当前配置已清除不代表历史备份/PITR/旧部署物理清除，也不代表供应商已撤销；这些需要单独核查。

真实耗时、错误样本、截图和尚未验证项均见 [执行记录](ai-byok-progress.md)。mock 测试、云端业务测试、模拟器与真机性能证据分别报告，不能互相冒充。
