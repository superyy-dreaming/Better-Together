# 交付与发布验收

日期：2026-11-18。Flutter iOS / Android MVP 及自定义 AI 已实现。新加坡内测环境现已运行“客户端压缩、Edge 先识别、用户确认后原图私有归档”。真实合成图验证了零预归档、确认后盖章、后台纪要及签名链接原图字节一致；故障路径也在模拟器观察到盖章后补齐纪要。测试环境和正式签名分发是不同里程碑。[实测证据](direct-recognition-acceptance.md) · [数据契约](direct-recognition-contract.md)。

## 已实现

- 中文页面与双平台导航：今日、打卡、纪要、计划、历史、小队、邀请、周报、个人设置、通知、隐私说明。
- Apple/邮箱验证码接口、固定时区建队、邀请链接与二维码、计划频率/可见性/下周修改。
- 小队邀请新增相机扫码入口与 8 位易辨认短码，支持复制、分组手输、旧邀请码兼容，识别后确认加入；详见 [邀请与扫码验收](invites-runbook.md)。
- 多图逐张验证与失败提示、提交即盖章、独立异步 AI、纪要字段来源、人工修订、计时、补卡和重打。
- 队内互动、严格过半质疑、逾期和戳、连续记录、个人及小队周报、公开周报投影、报告互动和长图导出。
- Supabase SQL/RLS/私有 Storage/Realtime/Edge Functions/Cron；照片哈希、队伍隔离、退出历史隔离、账户删除和持久媒体清理。
- 账号独立自定义 AI：Responses / Chat Completions、当前输入合成图片测试、保存、空密钥沿用、停用及清除。密钥服务端 AES-GCM 加密；错误不自动回退默认服务。
- APNs/极光的客户端和服务端接入代码，默认不主动请求系统通知权限。此项代码完成不等于真实推送送达。

## 已执行的本地验证

2026-11-19 补验：Xcode GUI 原生 hook 的 SDK 路径问题已修复，真机 Debug 构建及签名校验通过，Xcode 显示 `Running Runner on superpotato`。推送与 Apple 登录签名权限均保留。详见 [Xcode 构建验收](ios-build-verification.md)。

同日补验：Release 版本无需调试器冷启动通过；修复 Supabase Apple provider 与 Client IDs 后，用户确认真机 Apple 登录已进入首页。随后配置自定义 SMTP 与数字验证码模板，用户确认收到邮件验证码并在手机进入首页。详见 [登录配置验收](auth-acceptance.md)。

| 范围 | 实际证据 | 限制 |
| --- | --- | --- |
| Flutter | analyze 无问题，100 项测试通过；含邀请解析、相机错误恢复/关闭、防重复、验证码会话及既有业务；iOS Release 构建成功且已覆盖安装真机；用户确认 iPhone 相机打开和二维码识别成功 | 非真机 VoiceOver/TalkBack 验收；Android 物理相机识别仍待实测 |
| 数据库 | PostgreSQL 17 独立临时集群，15 份迁移、7 组 SQL 及双连接并发测试通过；覆盖照片/缓存原子登记、幂等重放、隐私和归类，见 [上传恢复](direct-media-repair-status.md) | 本地 auth/storage schema 为测试替身 |
| 配置检查 | 6 项合成配置测试通过；模拟器不再要求 Image Transform，保留权限/端点/密钥格式检查 | 不读取真实配置，不证明密钥有效或云端连通 |
| Edge | api/media/recognize/worker 类型检查与 117 项测试通过；覆盖两协议、本人配置、脱敏、错误不回退、失败保留盖章 | 测试中的供应商/Storage 请求为 mock；真实证据另列 |
| 周报长图 | 实际离屏绘制 780×4734 PNG，底部完整；本人权限、防重复、失败恢复测试通过 | 真实系统分享面板与云端分享统计待验 |
| iOS 原始流程 | iPhone 17 Pro Simulator 构建、安装及演示仓库核心流程通过 | 原始完整流程使用演示仓库和合成图片 |
| Android 原始流程 | API 36 Emulator debug 构建、安装及演示仓库核心流程通过 | 不是正式签名内测 APK，未完成本轮真实账号 Android 联调 |
| iOS 自定义 AI | 真实 Supabase 测试账号登录、bootstrap、设置入口、AI 设置元数据加载、必填校验、浅色与深色大字号原生 integration 通过 | 使用测试账号密码登录；不代表 Apple 或邮箱验证码流程已验收 |
| 视觉 | output/qa/ios-*.png、android-*.png；本轮包含设置、真实预览、ALL 盖章截图 | 未完成真实设备、横屏全流程与系统屏幕阅读器测试 |

本轮日志索引见 [直连识别实测证据](direct-recognition-acceptance.md)。早期演示仓库 integration 日志仍保留为 `ios-integration.log` 与 `android-integration.log`。

构建产物位于 app/build/ios/iphonesimulator/Runner.app 与 app/build/app/outputs/flutter-apk/app-debug.apk，分别只供 iOS Simulator / Android 开发验证。构建是否连接真实服务以入口和编译配置为准，不能将旧演示产物或 integration 测试入口当作正式发布版本。

## 已执行的真实服务验证

- 新加坡 Supabase 内测项目已应用至 015，部署 api、media、recognize、worker。此前配置 Vault Cron 时观察到的 3 次 Cron worker HTTP 响应均为 200，没有请求超时；这只是任务触发证据，不替代业务结果验证。
- 当前默认 AI 地址为 https://api.siliconflow.cn/v1，模型为 deepseek-ai/DeepSeek-V4.1-Flash，协议为 chat_completions。服务端保留用户选择的地址和模型，未擅自换模型。
- 同一服务在本地与已部署云端均通过合成图片和严格 JSON 探测。探测只证明该次请求的连接、图片输入和规定 JSON 返回成功，不代表真实照片分类准确率达标。
- 认证测试账号的自定义 AI get / test / save / 空 key 重测 / disable / delete 已实测通过。未将真实密钥放入客户端快照、源码或日志。测试账号仍保留供模拟器使用，不展示其登录凭据。
- 旧图片上传到 Image Transform 步骤时返回 403 FeatureNotEnabled。用户已明确改用客户端压缩与 Edge 识别，打卡无需再等待开通该能力；新识别、归档和盖章闭环已用真实服务与合成图分别验证，详见[逐阶段证据](direct-recognition-acceptance.md)。此结论仅针对打卡照片。

## 发布前仍需完成

1. 补充真实设备/多账号的多图严格多数、平票、手工改标签、截图待核实与权限联调。当前已有本地自动化覆盖；云端单图合成验证不能替代整个验收矩阵。
2. 完成 Android Apple Web OAuth、Realtime 多账号同步、周报生成/分享及账号删除的端到端检查。iOS 原生 Apple 与邮箱验证码登录已由用户真机验证。
3. 真机验证照片日期/旋转/HEIC、9 图、旧图/重复图剔除、AI 故障保留盖章、删除失败恢复、APNs/极光权限/送达/冷启动与通知分项。
4. iOS 邀请 URL 曾触发系统打开确认，但当次 Mac 锁屏阻止 CUA 点击确认，该系统交互尚未验收。HTTPS Universal Links / Android App Links 未配置真实域名；当前私测入口为 custom scheme 和邀请码。
5. 补齐运营主体、隐私政策、支持联系方式、数据保留与跨境说明，完成计划中的连通性和隐私评估。当前隐私页明确显示待补信息。
6. iOS 开发签名与真机启动已验证；仍需完成发布签名、APNs 和 Android release 签名/推送配置，执行不带参数的 python3 scripts/check_config.py。App Store Connect 上传及处理成功后才邀请 TestFlight 用户；Android 使用明确的内测发布证书。尚未交付正式签名 APK 或 TestFlight。
7. 真实设备烟测通过后开始 4 周、5–8 个小队内测，测量留存、完成率、归类准确率和报告打开/分享指标。这些指标目前没有实测结果。

## 已知产品与运行边界

- .local 目录权限 700，配置文件权限 600。配置检查仅验证结构与权限，不证明供应商密钥有效、DNS 安全或真实打卡链路通过。
- 自定义 AI 端点进行 HTTPS、公网 DNS/IP 与重定向限制；DNS 预检与 fetch 再次解析之间仍有重绑定竞态，最终隔离需要部署层出站规则或受控代理，不能声称应用层已完全消除 SSRF。
- 退出队伍后不再签发旧内容 URL，已发出的签名链接最多仍有效 5 分钟。
- 打卡用客户端 ≤1600px/2MiB JPEG 经 Edge 识别；原图仍私有存档并校验日期/去重。临时分析 data URL 仅服务端可读，24 小时后清像素留文本；原图与缩图摘要绑定不能证明两者像素内容一致，该信任边界需如实告知。
- 缺少可靠原图 EXIF 且不是可识别运动截图时，该图会被拒绝；不能把缓存文件时间当成拍摄时间。
- 周报建议依据真实完成频率，当前未收集“时段冲突/漏提醒/难度”等原因，不生成臆测原因。
- Cron 按分钟扫描；当天规则与幂等已测，但停机跨日后的逾期历史补扫尚未实现。小队连续记录按当前成员的当前分享期间计算，未保存成员变化时的历史连续快照。
- HealthKit/健康自动对账按计划仅预留入口，当前不读取健康数据。

## 设计依据与回滚

OJO Design Skills 已安装为 ~/.codex/skills/app-ui-ux-best-practices，结合 ui-ux-pro-max、Impeccable 与原型，规范见 [DESIGN.md](../DESIGN.md)。appledesign skill 不可用，以 Apple 官方 HIG 和 Impeccable 原生参考代替；没有把浏览器页面检查当作原生验收。

原始 README、HTML、PDF 保留；当前未创建 Git 提交或推送。远端 Supabase 已部署并包含内测配置，不能再将其描述为“未修改远端”。本地代码回退不删除 .local 密钥或签名文件；远端按 [backend-runbook.md](backend-runbook.md) 暂停任务和回退函数，保留数据库、Storage、队列及加密配置，禁止 reset/drop 用户数据。
