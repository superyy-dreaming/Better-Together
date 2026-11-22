# 后端部署与验证

部署对象是新加坡区内测 Supabase 项目。2026-11-21 已追加 020 并部署无后端 AI Key 的 api、recognize、media、worker。AI 从设备直连用户站点，部署顺序与回滚以 [BYOK runbook](byok-rollout.md) 为准。

2026-11-21 已追加 017–019 并更新 api、recognize、media、worker：灵活计划、独立分页、按需媒体签名、私有缩略图和头像归档已部署，旧接口保留。部署后核对 profile 布尔状态与有效时区、计划当日计数、历史日历及分页；具体证据和覆盖边界见[本轮优化验收](flexible-experience-acceptance.md)。后续回滚必须兼容新增排期和媒体字段，不能用旧星期编辑器覆盖新频率。

## 安全配置

1. 打包配置只包含 Supabase URL、anon/publishable key 等公开配置。AI Key 仅由用户在 App 设置输入并进入本机安全存储；service role、JOB_SECRET、SMTP、APNs 与极光私钥仍只在服务端。不得把 .local/server.env 编译进移动应用。
2. .local/ 使用权限 700，配置文件使用 600，均不进入 Git。python3 scripts/check_config.py --simulator 检查模拟器/AI 必需项；不带参数另检查签名与真机推送。脚本不输出值、不发请求，检查通过不代表云功能已开通。
3. 服务端禁止 OPENAI_*、AI_SETTINGS_ENCRYPTION_KEY 和用户 AI 密文存储。AI 只使用当前设备、当前账号的配置；首次预填地址和模型不是默认服务。
4. 旧 AI 主密钥和密文表已移除，不得恢复或从旧配置迁移至客户端；持有人须在供应商处撤销旧 Key。历史备份/PITR/旧部署物理清除另行核查。
5. 设置页只回显无密钥元数据。改地址须输入新 Key；测试使用合成图且不保存。停用／清除后跳过 AI，保持正常打卡；不回退其他服务。
6. iOS 原生 Apple 登录需在 Supabase 启用 Apple provider，并登记实际 Bundle ID；用户真机登录已通过，见[登录配置验收](auth-acceptance.md)。自定义 SMTP 已通过 TLS/身份认证并配置到云端，confirmation/magic_link 已改为数字验证码；用户已确认收到验证码并在手机进入首页。Android Apple Web OAuth（含 Services ID、client secret、回调 bettertogether://auth/callback）及 APNs 仍需分别配置和验收；不要将密码登录成功等同这些能力已启用。
7. AI 地址仅接受 HTTPS，禁止 URL 凭据、查询参数和重定向。请求由设备发送，不存在服务端供应商出站代理。

## 后续更新部署顺序

1. 确认 CLI 当前链接的是该内测项目，核对区域、迁移历史与备份。不在已有业务数据库 reset schema。
2. 仅更新非 AI 的服务端配置，通过 env-file 注入且不打印值；不得覆盖正式签名证书。AI Key 不得进入该文件。
3. CLI 3.2 使用 `supabase db push --remote=<project-ref> --dry-run` 核对，再去掉 dry-run 执行。已部署迁移不改写，只追加修复；tests/bootstrap.sql 仅用于本地替身，禁止运行到云端。
4. 按 BYOK runbook 部署 api、recognize、media、worker。recognize 为升级兼容入口，不转发；worker 只执行非 AI 任务。函数自行验证 JWT 或 JOB_SECRET，verify_jwt=false 不代表匿名授权。
5. 保留 Vault 的 better_together_url 与 better_together_job_secret，后者需与 Edge JOB_SECRET 一致，再按需运行 supabase/deploy/schedule.sql。不要把 Vault 的值写进迁移或终端日志。Cron 每分钟触发 worker，照片提交本身只落库并盖章。
6. 用专用合成测试账号执行下述探测；记录响应状态、脱敏错误代码、job 状态与可观察业务结果，不保存 API key、JWT、邮箱密码或私有图片 URL 到 QA 日志。

## 当前实测与剩余范围

- 合成图经真实默认供应商识别，预览时该批次无媒体登记和 Storage 对象；确认后立即盖章，后台纪要 ready，私有签名链接返回的字节与提交原图 SHA256 一致。见[实测记录](direct-recognition-acceptance.md)。
- 模型不可用时的探测确认 pending、未自动切换供应商、ALL 盖章及清除专用账号临时设置。探测随后因 `NETWORK_UNAVAILABLE` 中断，原始结果应保留 failed。另行读取业务状态并在模拟器观察到盖章保留且纪要已补齐；这与脚本退出状态分别记录。
- 真实账号自定义 AI get/test/save/空 key 重测/disable/delete 及 iOS 设置流程已验证，iOS 原生 Apple 与邮箱验证码登录已由用户真机验证。生产接纳真实用户照片前仍须完成隐私/跨境评估、部署端点出站隔离确认。Android Apple Web OAuth、跨账号 Realtime、周报 Cron、账号删除、APNs/极光及正式签名分发需分别验收。
- 对确切照片身份的登记结果未知时保留私有对象，同身份重试；不能仅凭请求失败删除对象，详见[媒体生命周期](agent-media-lifecycle.md)。无法登记的孤儿目前不自动回收；人工处理前须核实归属及引用，避免删掉已盖章凭证。

## 本地验证与运行观察

- Flutter analyze 通过、85 项测试通过；Edge 四入口 Deno check 及 117 项测试通过；PostgreSQL 17 临时集群执行 15 份迁移、7 组 SQL 及双连接并发测试通过；另有 6 项配置测试通过。外部依赖的本地用例采用 mock，不能替代[云端证据](direct-recognition-acceptance.md)。
- 数据库命令：bash supabase/tests/run.sh，需要 PostgreSQL 17 的 initdb、pg_ctl、psql。脚本使用私有 Unix socket 临时集群并自动清理，不读取远端地址。
- Edge 命令：npx --yes deno test --allow-env --allow-read supabase/functions/_shared/。供应商与 Supabase 网络依赖使用合成 mock，测试不需要真实 key。
- 观察 jobs、push_outbox 的 status/attempts/last_error 或 error，以及函数结构化事件。processing 只表示租约占用，过期租约可重新领取；AI 故障不撤销盖章。
- 设备配置或服务暂不可用时保留 pending，不撤销盖章。App 当天自动补识别，过期可主动补生成；周报由本人打开时在客户端生成，不执行服务器 AI 重试。
- Cron HTTP 响应只证明一次触发结果。请求超时不代表业务失败；应查看 job 状态、租约与业务结果，不因观测错误重置记录。推送尽力投递，应用内通知是可靠记录。
- SQL 生成可回溯的周报事实和称号，AI 只选择已经验证的事实句。建议仅依据完成/应完成天数调整频率，不编造漏打原因。

## 回滚

需要暂停 AI 时停用设备配置，不应为 AI 停掉包含通知、排期和清理的 Cron。回滚仅部署无后端 Key 的兼容版本，保留数据和非 AI 队列；追加修复迁移，不删除或重置数据库。

用户配置清除是明确的账号操作，不是部署修复手段。不要删除测试账号、重置密钥、批量清空任务或媒体来掩盖服务权限问题。

## 依据

- [Supabase：Scheduling Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)，2026-11-18 查阅：pg_cron + pg_net + Vault。
- [Supabase：Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)。业务表启用 RLS，客户端写入由受控 RPC 校验，私有照片使用短时签名 URL。
- [自定义 AI Worker 接入记录](custom-ai-worker-status.md) 与 [后端加密及隔离记录](custom-ai-backend-status.md)。

## 分组打卡版本

已追加 023/024，api 放行 `submit_checkin_batch`，事务校验同账号/同批次照片并返回所有记录 ID。原单条接口保留。回滚使用无后端 AI Key 的兼容客户端，保留拆分数据；验收和限制见 [分组打卡验收](batch-checkin-acceptance.md)。新版 Supabase CLI 的无交互部署在已有用户部署授权下使用 `--remote --yes`，先 `--dry-run` 核对唯一目标和新增迁移，不执行 reset。
