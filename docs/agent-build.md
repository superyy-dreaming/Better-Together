# 原生构建入口

使用 `bash scripts/flutter.sh <Flutter 参数>`。脚本只影响当前进程，不修改系统 Xcode 选择。

Xcode 的 Build/Run/Archive 不经过终端入口。共享 Runner Scheme 的 prepare，以及 Target 的 build、embed_and_thin 阶段必须通过 `scripts/xcode_backend.sh`，确保 GUI 与 CLI 使用相同的 SDK resolver 和本机调试免代理环境。只修终端 wrapper 不算修复 GUI 构建；升级 Flutter 若重写这些阶段，应重新核对并直接用 Xcode/xcodebuild 验证。

Dart 原生 build hooks 会过滤 DEVELOPER_DIR，却保留 PATH。系统选中 Command Line Tools 时，objective_c 的 xcrun SDK 查询会返回空值，表现为 `Bad state: No element`。先检查 SDK 查询、hook 环境和 Xcode 路径，不通过重试或修改依赖缓存解决。项目 wrapper 显式使用已安装的完整 Xcode，脚本路径进入 hook 缓存键。

若 Xcode 安装位置改变，更新 scripts/xcode-tools/xcrun。验收为 iOS Simulator 实际构建和启动成功。发布前仍须通过本地安全配置选择开发团队与签名，不复用模板自动探测的团队身份。

Flutter drive/run 需要直连本机 VM Service。若代理环境没有 NO_PROXY，应用会停在调试器等待状态，工具提示连接超时。先使用直连 HTTP getVM 证实服务存活，再给当前进程增加 loopback 免代理规则；不要通过延长超时掩盖路由错误。脚本已限定 localhost/127.0.0.1/::1。

iOS 真机上的 Flutter Debug 使用 JIT，iOS 14+ 不能从桌面独立冷启动。供用户日常试用时选择共享 Scheme `Better Together Device`，其 Run 使用 Release 且不附加调试器；`Runner` 保留 Debug 供断点、热重载和模拟器开发。也可运行 `bash scripts/flutter.sh build ios --release --dart-define-from-file=../.local/client.json --no-pub` 后覆盖安装，不卸载清数据。验收必须包含停止旧调试会话后无调试器冷启动，不能将 Xcode Debug 启动成功当成桌面启动成功。

模拟器使用共享 Scheme `Better Together Simulator`（Debug）或 `Runner`，打开 `app/ios/Runner.xcworkspace`。不要把 `Better Together Device` 的 Release Run 与模拟器搭配；Flutter 不提供模拟器 Release 引擎，Swift Package 插件会报 `Flutter/Flutter.h file not found` / `Unable to resolve module dependency: Flutter`。遇到同类错误先查 Scheme、Configuration、Destination 与 prepare 阶段的产品目录，不先清空 Pods、DerivedData 或改插件搜索路径。

原生集成测试会将 `Flutter/Generated.xcconfig` 中的 `FLUTTER_TARGET` 指向测试文件。交还 Xcode 或安装日常版本之前，必须用明确的 `--target lib/main.dart` 恢复。模拟器可执行 `bash scripts/flutter.sh build ios --simulator --debug --config-only --target lib/main.dart --dart-define-from-file=../.local/client.json --no-pub`，再从上述 Debug Scheme Run；真机 Release 构建也应明确指定 main。验收包含正式应用登录页或首页，不以测试成功页代替。
