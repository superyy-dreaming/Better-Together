# Xcode 构建修复验收

## 模拟器 Flutter 模块缺失

2026-11-21，Xcode 使用 `Better Together Device` + iPhone 模拟器时出现四项插件编译错误：`Flutter/Flutter.h file not found` 和 `Unable to resolve module dependency: Flutter`。失败构建日志确认使用 Release-iphonesimulator，运行方案的 Run 配置为 Release；Flutter 官方不支持 iOS 模拟器 Release。

新增共享 `Better Together Simulator`，使用 Debug；保留真机 Release 方案。恢复 `FLUTTER_TARGET=lib/main.dart` 与本地客户端配置，避免前一次 integration_test 入口残留。

- 直接 xcodebuild 使用新 Scheme 和 iPhone 17 Pro 模拟器，`BUILD SUCCEEDED`：`output/xcode-simulator-build-fix.log`。
- 从 Xcode 按 Run，状态显示 `Running Runner on iPhone 17 Pro`，错误列表为空；模拟器展示正式 App 登录页：`output/qa/xcode-simulator-build-fixed.png`。
- 不修改插件、Flutter SDK 或证书，不清除模拟器账号与数据。回滚只涉及新增 Scheme；原 `Runner` 仍可用于 Debug。

依据：[Flutter build modes](https://docs.flutter.dev/testing/build-modes)，2026-11-21 查阅。模拟器运行 Debug，真机日常试用运行 Release。

## 原生 hook SDK 查询

2026-11-19，针对 Xcode Run Script 的 `Command PhaseScriptExecution failed with a nonzero exit code`。

最新失败日志的根因是 objective_c 9.6.4 原生 hook 调用 `xcrun --show-sdk-path --sdk iphoneos` 得到空输出，随后触发 `Bad state: No element`。系统命令行工具选择仍为 Command Line Tools。终端 Flutter wrapper 已提供 SDK resolver，但 Xcode GUI 原先直接调用 Flutter backend，没有继承此 PATH。

新增 `scripts/xcode_backend.sh`，供 Runner Scheme 的 prepare 与 Target 的 build、embed_and_thin 共用。它加入已有项目 SDK resolver 与本机调试免代理规则，再转交 Flutter backend。不修改系统 Xcode 选择、依赖缓存或证书，不移除推送和 Apple 登录能力。

验证：

- shell 语法和 Xcode project plist 校验通过。
- 直接执行 xcodebuild，使用 Runner.xcworkspace / Runner / Debug / generic iOS，结果 `BUILD SUCCEEDED`。日志：`output/qa/xcode-device-build-fix.log`。
- 真机产物 `codesign --verify --deep --strict` 通过；嵌入的专用 profile 与实际签名均包含 `aps-environment=development` 和 Apple 登录 `Default`，应用标识匹配。
- Xcode 界面显示 `Running Runner on superpotato`，错误列表为空；控制台显示 Flutter 与 Supabase 初始化。后续两份 GUI 构建日志均不再含 SDK 查询异常、脚本退出错误或描述文件不匹配。

截图中的通配符描述文件错误属于此前构建状态；本轮直接构建已使用具备所需权限的专用描述文件。开发签名及启动通过不等于 APNs 实际送达、Apple 登录闭环或 TestFlight 发布验收。

回滚范围仅为新增脚本与 Runner 三处脚本入口；不要删除 profile、证书或通过移除产品能力规避问题。若恢复原入口，本机 Command Line Tools 选择下将重新暴露同一 hook 错误。

## 真机桌面独立启动

Debug 构建通过仍不能保证桌面启动。用户随后报告 Flutter 的 iOS 14+ JIT 启动限制，根因为之前安装的是 Debug 版。新增共享 Scheme `Better Together Device`：Run 使用 Release 与 PosixSpawn、不附加 LLDB；原 Runner Debug 保留供开发。

Release 构建已通过并覆盖安装至 superpotato。签名校验通过，当前开发安装的实际签名/profile 均为 development APNs，保留 Apple 登录能力；App.framework 含预编译 `_kDartSnapshotText`，无 Debug kernel_blob.bin。安装未卸载或清除用户数据。Xcode 当前选中新的真机 Scheme。

首次无调试器启动请求被 iPhone 锁屏拒绝；用户解锁后完成验证：devicectl 未附加 LLDB 即启动成功。随后再次终止并以不附加调试器、不连接控制台的方式冷启动，系统返回 Launched application，后续进程查询确认新 Runner 进程仍在。证据：`output/qa/ios-standalone-cold-start.log`、`ios-standalone-cold-process.json`。此验证证明 Release 独立进程启动，未将其等同于全部业务页面或人工桌面点击验收。

依据：[Flutter build modes](https://docs.flutter.dev/testing/build-modes)（2026-11-19 查阅），及设备上 Flutter 的 iOS Debug 启动提示。

## 本轮分组打卡交付的重新构建

2026-11-21，在 iOS 26.5 Simulator 和已连接的 superpotato 上验证。清理 Flutter 产物、重新 pub get / pod install，并恢复 `lib/main.dart` 与 `.local/client.json` 后，直接调用完整 Xcode 26.6 的 `xcodebuild`：

- `Better Together Simulator` / Debug / iPhone 17 Pro：`BUILD SUCCEEDED`，安装和 `simctl launch` 成功，正式 App 显示登录页。证据 `output/qa/batch-xcode-simulator.log`、`batch-final-simulator.png`。
- `Runner` / Debug / generic iOS：`BUILD SUCCEEDED`，证据 `output/qa/batch-xcode-device-debug.log`。
- `Better Together Device` / Release / generic iOS：`BUILD SUCCEEDED`，证据 `output/qa/batch-xcode-device-release.log`。
- Release 深层签名校验通过；Bundle ID 为 `app.bettertogether.betterTogether`，最低 iOS 15.0，实际 Team 与 profile 匹配，Apple 登录 entitlement 保留，开发安装的 APNs 为 development。证据 `output/qa/batch-release-signature.json`。签名通过不等于推送送达测试。
- 独立原生自动化在模拟器验证两套外观的预览、下一步识别、照片移动、整组改计划、纪要编辑和最终拆条，结果见 `output/qa/batch-native-flow.log`。测试使用模拟识别结果，不声称重新测量真实供应商性能。

Xcode 脚本补充完整 `DEVELOPER_DIR`，并在误用 Release/Profile 构建模拟器时提示选择 Simulator / Debug，避免再次只看到 Flutter 模块缺失。不要为解决这个错误卸载插件、移除 Apple 登录能力、重置证书或删除用户应用。

截至自动验证，全局 `xcode-select -p` 仍为 CommandLineTools。`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 需要用户在本机输入管理员密码，自动化无权限完成；项目两条构建入口已独立固定完整 Xcode。Mac 当前锁屏，未把 GUI 点击 Run 计为本轮通过。

本轮使用 `output/xcode-batch-build` 隔离原生生成产物，未删除 Xcode 其他项目缓存。恢复或回滚见 `docs/batch-checkin-acceptance.md`；保留已有数据、签名身份和无后端 AI Key 架构。

Release 已覆盖安装到 superpotato，未卸载 App 或清理数据。`devicectl` 无调试器启动成功，见 `output/qa/batch-device-install.log`、`batch-device-launch.log`。后续同类排查先读 [原生构建约束](agent-ios-build.md)。
