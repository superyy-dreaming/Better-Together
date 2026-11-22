# 分组打卡与 Xcode 构建验收

本次以用户确认的“预览 → 下一步识别 → 分组确认 → 归档盖章”为准。经典纸面与团团外观沿用现有设计系统，iOS 使用系统字体、安全区和至少 44pt 触控目标。沿用已读取的 ui-ux-pro-max、Impeccable operate/craft-floor/native audit；无 appledesign skill，以 Apple 官方 HIG 为替代。未引入新的 UI 组件依赖。

## 已交付流程

- 选图只读原图与 EXIF 并显示缩略图，可增删、切换照片/截图类型。点击下一步才处理整批，最多 4 张并发；重复点击不会再次启动。
- 逐张成功且置信度至少 80% 才采用计划建议，按计划拆分；无确定建议、低置信度和失败照片进入 ALL，不把一批照片强行投成同一个计划。已知日期不符的照片继续剔除。
- 分组卡支持单张移动、整组改计划和纪要编辑。整组移动会带走手写纪要；每张照片原本的摘要与字段独立保留。后台结果不会覆盖手动计划和已编辑纪要。
- 返回整理可重新增删照片。草稿在应用内跨页面保留；未确认原图不上传。普通系统挂起保留内存任务，归档后的待补识别继续使用已有持久化任务队列。未归档草稿不承诺进程被系统杀死后恢复。
- 所有保留照片完成归档后，单次数据库事务创建分组记录。上传部分失败时显示原位错误，重试复用已归档照片，不提前生成不完整记录。
- 记录详情保留逐图摘要、字段来源和补生成入口，并提供已加载的同批记录跳转；历史列表继续逐条显示。
- 旧单条接口保留。新接口校验账号、照片所属批次、未使用状态、计划归属、来源、低置信度与幂等键；字段来自已经独立校验的照片归档数据。补卡额度按批次计，仍要求原计划；盖章通知保持原有行为。

## 验证证据

| 项目 | 结果与证据 |
| --- | --- |
| Flutter 静态检查 | 通过，`output/qa/batch-analyze.log` |
| Flutter 全套测试 | 最终代码全套 160 项通过；其中草稿状态机 13 项通过。`batch-flutter-tests.log`、`batch-targeted-tests.log` |
| 两主题分组操作 | 375 / 768 / 1024 / 1440，大字号、手机深色和宽屏浅色，8 个界面流程及 1 个仓库事务测试通过。`batch-ui-tests.log` |
| Edge | 48 项测试通过，新批次操作确实转发至单次 RPC 并返回全部记录；api 类型检查通过。`batch-edge-tests.log`、`batch-edge-contract.log`、`batch-edge-check.log` |
| 数据库 | 本机临时 PostgreSQL 跑历史与追加迁移、规则、权限、BYOK、频率、批次和并发登记全部通过。新测试覆盖跨批次事务回滚、重复照片、重复确认、同日追加、低置信度、编辑后迟到结果、补卡规则和盖章通知。`batch-sql-tests.log` |
| iOS 原生流程 | `flutter drive` 在 iPhone 17 Pro / iOS 26.5 Simulator 通过，使用明确的合成图与模拟识别结果，未调用真实 AI。验证预览零请求、下一步 3 次逐图请求、单张移动、整组改计划、手写纪要、最终 3 图 / 2 记录。`batch-native-flow.log` |
| 云端业务 | 专用合成账号真实上传、事务拆条、详情读取、重复提交和 pending ALL 盖章通过；确认前无 checkins，归档后各记录仅含自己的照片与摘要。不是模型识别准确率测试。`batch-cloud-smoke.json` |
| 发布 | 023 批次接口与 024 兼容修复追加迁移、api Edge Function。预检只列出相应新增迁移；未清空/重置数据库、未改写旧迁移、未触碰真实用户记录。见 `batch-migration-*`、`batch-compatibility-*`、`batch-api-deploy.log` |
| 收尾检查 | 最终模拟器增量构建、安装和正式入口启动成功。客户端源码、Edge 源码和本次追加迁移的 `sk-` 长密钥模式匹配为 0；Edge 源码 `.transform(...)` 调用为 0；Generated.xcconfig 确认指向 `lib/main.dart`。这是限定范围的静态检查，不代表历史日志或备份的物理清除证明。 |

截图：`output/qa/ios-batch-{classic,tuantuan}-{preview,grouped,edited,stamped}.png`。截图是原生模拟器实际界面，图像本身带 TEST 标识，AI 返回值是测试夹具，不是模型准确率或速度证据。

## Xcode 与安装

模拟器 Debug、真机 Debug/Release 的直接 xcodebuild 均成功；Release 签名通过并已覆盖安装至 superpotato，devicectl 无调试器启动成功。详见 `docs/ios-build-verification.md` 的本轮验证。模拟器使用共享方案 **Better Together Simulator / Debug**，真机桌面独立运行使用 **Better Together Device / Release**。Flutter 官方不支持 iOS Simulator Release，不将这个模式列为通过。

已清理 Flutter 构建产物，重新 pub get / pod install，恢复 Generated.xcconfig 的 `lib/main.dart` 和安全客户端配置；客户端配置只有公开 Supabase 与 App 配置，不包含 AI Key。Xcode GUI 脚本与 CLI 都使用项目 SDK resolver；误用真机方案构建模拟器时会给出明确的 Debug 方案提示。

全局 `xcode-select` 切换需要 Mac 管理员权限。当前自动化无法输入管理员密码；已请用户在自己的终端执行切换。项目构建使用明确的完整 Xcode 路径，不依赖全局 CommandLineTools。Mac 锁屏时无法替用户点击 Xcode Run，CLI 原生构建与模拟器启动单列作为证据。

## 验收边界与回滚

- 本次未重新测试真实 Apple/邮箱授权、真实模型的归类准确率或网络耗时、跨设备 UI 同步，也未用模拟器照片流程冒充真实摄像头测试。原有 BYOK 直连和私有媒体链路保持；新代码不接触 Key、供应商配置或服务端代理。
- 原生流程已验证普通导航恢复；未做 iOS 杀进程后恢复未归档草稿。归档后恢复由原有持久队列处理，单元测试继续覆盖账号切换与迟到结果保护。
- 回滚客户端到兼容的无后端 AI Key 版本即可恢复旧单条提交；保留 023/024 和已经拆分的记录、照片、纪要。接口修复使用追加迁移，不删除生产数据，不恢复旧 AI 代理或服务端 Key。
- 当前工作区没有 Git 仓库，本轮未创建 commit 或推送。
