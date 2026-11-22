# 同步、照片与灵活计划验收

2026-11-21。保留经典纸面与团团陪你两种外观，更新数据读取、照片浏览、计划频率、头像和选图入口。以下区分本地回归、原生运行与真实云端证据；测试通过不等同所有真实设备场景均已验收。

## 已实现范围

- 首屏使用 `bootstrap_v2` 返回摘要和稳定媒体引用；动态、历史、计划、通知与周报独立分页，详情按 ID 读取。同一范围合并正在进行的刷新，同账号后台刷新保留当前内容；保存错误与保存成功后的刷新异常分别呈现。已移除为媒体签名每四分钟全量刷新记录的机制。
- 私有图片先批量验证访问权限，再读取本机文件。缓存键包含账号、媒体引用、内容版本和规格，签名 URL 不作为文件身份；默认保留七天，下载后按 200 MB 上限清理。媒体服务异常仅影响对应图片。动态和纪要支持全屏查看、双击缩放、双指缩放、翻页和返回；放大后优先拖动图片。
- 计划支持固定星期、每周完成 1～7 天、从开始日期每隔 1～365 天执行。新增作息、饮水、冥想及可编辑模板，取消三计划上限；列表支持搜索、筛选和分页。频率编辑保留版本历史、下周生效。每周目标同日多条只计一天，额外完成单独反馈，完成率不超过 100%。
- 日程连续完成次数与连续达标周分开统计。每周目标不产生每日漏卡；周一 00:30 结算不足，补卡后可更新。周日 20:00 阶段周报、周一 12:05 同份周报定稿，按小队固定时区执行。
- 头像在客户端规范为 512×512 JPEG，后端核验后直接写私有桶，不调用 Image Transform；提供十二款小熊。个人资料局部更新保留布尔暂停状态和小队有效时区。
- 打卡主入口改为“现在选一张”，统一选择拍照或相册；移除独立相册/运动截图按钮及运动计时入口。逐图确认照片或记录截图类型，最多九张；历史计时数据继续可读，新提交不带计时字段。
- 原图归档与缩略图生成分离。缩略图只用已校验的分析图派生，不处理或重传旧原图。没有缩略图的旧记录首次查看下载原图，之后复用缓存。

## 验证证据

| 层级 | 结果与边界 | 证据 |
| --- | --- | --- |
| Flutter | analyze 无问题，135 项测试通过。涵盖会话隔离、刷新合并、后台重验保留后续分页、缓存授权与文件复用、频率和界面回归 | `output/flexible-analyze.log`、`output/flexible-flutter-tests.log` |
| Edge Functions | 125 项测试通过，四入口检查及最终 api/worker 检查通过。外部依赖故障为合成注入 | `output/flexible-final-deno-tests.log`、`output/flexible-deno-check.log`、`output/flexible-final-deno-check.log` |
| PostgreSQL 17 | 全部迁移、既有业务回归、新频率/阶段周报/局部资料回归及双连接并发测试通过；使用本机临时数据库 | `output/scope-final-db-tests.log` |
| iOS 与 Android 原生 | 两平台双主题、浅深色、大字体、主题持久化测试通过 | `output/flexible-ios-test.log`、`output/flexible-android-test.log` |
| 新交互原生回归 | 两平台小熊选择器、选图菜单与取消、无旧按钮/计时、周目标与间隔表单、双击缩放、放大禁翻页、还原翻页、返回通过 | `output/flexible-new-ios-test.log`、`output/flexible-new-android-test.log` |
| Xcode 模拟器 | 新 `Better Together Simulator` Scheme 使用 Debug；直接 Xcode 构建成功，并在 GUI 启动到登录页，四项 Flutter 模块错误消失 | `output/xcode-simulator-build-fix.log`、`output/xcode-simulator-gui-verification.json`、`output/qa/xcode-simulator-build-fixed.png` |
| 云端读取 | 同一合成账号的新旧读取、keyset 分页、计划详情和私有图片访问通过 | `output/scoped-cloud-smoke.json` |
| 云端写入 | 头像上传及引用通过，随后恢复原头像；同计划同日两条记录只计一天；缩略图任务与私有读取通过 | `output/flexible-write-smoke.json` |
| 019 云端复核 | 局部资料类型和时区、计划今日计数、历史日历与分页只读验证通过 | `output/scoped-final-cloud-smoke.json` |

原生回归使用本机 Demo 数据并恢复原偏好，不代替真实照片选择、真实相机权限或两个真人账号的联合测试。运行截图位于 `output/qa/ios-flexible-*.png` 与 `output/qa/android-flexible-*.png`；已检查小熊选择器与计划表单等主要布局。

缓存测试使用真实临时文件和可观测下载替身：更新签名后授权请求增加，但图片正文下载仍为一次；并发同图只下载一次；撤权后拒绝返回已有文件，换账号后清理并通知已渲染图片。该证据证明缓存逻辑，尚不是大量真实照片的网络抓包或存储压力基准。

## 同规模性能比较

对同一云端合成账号、三条记录与三张照片，在同一测试环境各读取三次：

| 指标 | 原 bootstrap | bootstrap_v2 |
| --- | ---: | ---: |
| 三次耗时 | 3940 / 1390 / 1635 ms | 1257 / 783 / 788 ms |
| 中位耗时 | 1635 ms | 788 ms |
| JSON 大小 | 10923 bytes | 9780 bytes |

该样本中位耗时下降约 **52%**。主要改变是记录摘要不等待逐图签名；该结果仅适用于本次小规模合成数据，不能外推为所有账号、弱网或大队伍的稳定提升。后续写入测试增加了记录数量，不与以上三条记录基线直接混算。

云端新照片缩略图为 24946 bytes，原图为 39047 bytes。旧照片探测返回原图大小，符合首次查看回退原图的规则；未批量重传旧数据。

## 部署与原生产物

迁移 017、018、019 已按追加顺序部署至现有内测项目，api、recognize、media、worker 已升级；019 与最终 api/worker 的部署结果记录于 `output/flexible-final-deploy-*.log`。旧读取接口保留；旧客户端不能用星期规则覆盖新频率计划。

- iPhone `main.dart` Release 构建完成，`codesign --verify --deep --strict` 通过；已覆盖安装至 superpotato，并通过 devicectl 无调试器启动。未卸载或清除账号数据，未安装 integration_test 入口。产物不含 Debug kernel，保留 Apple 登录能力；当前开发安装使用 development APNs。证据：`output/flexible-ios-release.log`、`output/flexible-ios-release-verification.json`、`output/flexible-iphone-install.log`、`output/flexible-iphone-launch.log`。这不等同 TestFlight 发布或推送送达验收。
- Android 本轮已完成模拟器构建与原生回归。安全配置中的签名模板尚未填写 storeFile、密码与包标识，未生成新证书，**尚未交付可分发的签名 Release APK**。不得把模拟器安装包当作内测签名包。

## 尚未覆盖的边界

- 真实 iPhone 相册/拍照权限、混合多图选择、头像裁切手感及双指缩放仍应做真人 smoke；原生自动化主要验证菜单与合成图片浏览。明确不合格原图在归档阶段逐张拒绝，不声称全部拍摄日期都已在本地预览阶段完成核实。
- AI 候选计划查询有数量边界，候选过多保留 ALL 并允许搜索选择。分类过滤 SQL 已具备，但没有单独先识别类别再做无限制候选匹配的链路。生活照片不会用于推测饮水量、睡眠或冥想时长。
- 阶段周报、定稿和补卡边界已通过真实 PostgreSQL 回归；尚未以跨周真人活动等待云端 Cron 完整观察。大规模计划分页、跨账号实时权限撤销与弱网缓存清理仍需要内测持续验证。
- 缩略图上传与软删除并发已用六项故障注入覆盖。只有匹配同一 owner/batch 的明确删除标记才允许清理其派生缩略图；关联结果未知不删对象。若媒体行在上传后被硬删除且缺少可核验删除凭据，可能保留不可公开访问的孤儿缩略图，需人工核对。原图绝不以超时作为删除理由。
- Xcode 仍提示 `sign_in_with_apple` 尚未支持 Swift Package Manager；当前兼容 CocoaPods 构建通过，该警告不是本轮 Flutter 模块缺失错误，但升级 Flutter 前需要复核插件兼容性。

## 回滚边界

回退使用兼容当前数据库的已验证客户端/函数版本。数据库仅追加纠正迁移，保留计划版本、原图、记录和已生成报告；不通过 drop/reset、删桶、重置账号或清空缓存服务端状态回滚。需要暂停后台任务时遵循 [后端 runbook](backend-runbook.md) 的调度暂停与恢复流程，保留队列、密钥和 Vault 配置。

客户端故障优先回退可兼容新频率的版本；旧版本遇新频率应提示升级。媒体故障可继续展示记录与局部重试图片，不能把图片不可读或刷新失败解释为盖章未保存。
