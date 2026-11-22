# iOS 构建排查约束

遇到 Xcode 构建失败、Flutter 模块缺失或独立启动失败时读取。

1. 先查实际失败构建的 Scheme、Configuration、SDK 和 `xcode-select -p`。完整 Xcode 路径为 `/Applications/Xcode.app/Contents/Developer`；先复现失败，不能直接删除缓存、profile 或证书。
2. 打开 `app/ios/Runner.xcworkspace`。iOS Simulator 使用 `Better Together Simulator` / Debug；Flutter 不支持 Simulator Release。真机桌面独立试用使用 `Better Together Device` / Release，Debug 独立启动与正常编译是不同验收项。
3. CLI 使用 `scripts/flutter.sh`。GUI Target 和 Scheme 的 Flutter 脚本共用 `scripts/xcode_backend.sh`；Dart native hook 会剥离部分环境变量，保留项目 `scripts/xcode-tools/xcrun` SDK resolver，不直接改 Flutter SDK 或插件缓存。
4. integration_test 构建会改写 Generated.xcconfig 的 FLUTTER_TARGET。交付前必须恢复 `lib/main.dart` 与 `.local/client.json`，再构建正式 App。不得把测试账号配置或服务端配置带入交付包。
5. 仅清理本项目生成产物、保留锁文件、重新解析依赖。不要全盘清除其他工程 DerivedData。工具链全局切换需要用户在本机输入管理员密码，不能索取聊天密码或绕过 macOS 提权。
6. 验收分别记录静态检查、单元/Widget 测试、原生构建、模拟器安装启动、真机签名与 Release 独立启动；任何一项不能冒充其他项。覆盖安装保留账号和数据，不先卸载用户应用。
7. 原生 UI 测试匹配项目实际使用的 `material_ui` / `cupertino_ui` 组件类型。`WidgetTester.pageBack()` 内置的 Flutter Material 类型可能匹配不到本项目的返回按钮，此时点击项目导入的 `BackButton`，不能把测试查找失败判为产品返回失效。`PageBody` 是惰性列表，屏幕外控件先用 `scrollUntilVisible` 构建并滚入视野，再操作；`ensureVisible` 只适用于已经挂载的元素。

依据：[Flutter build modes](https://docs.flutter.dev/testing/build-modes)；具体本机证据见 [iOS 构建验收](ios-build-verification.md)。
