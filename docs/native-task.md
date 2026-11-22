# 原生配置实施任务

分配给 client_data agent：继续直接实施，不只审查。

1. 负责 Flutter 原生 iOS/Android 权限、显示名称、Apple 登录 entitlement、deep links、APNs/JPush token 注册。
2. 新建 app/lib/platform/push_service.dart，提供 start(repository,onOpen)、requestPermission、dispose，明确记录调用方式。不要改 root 的 UI、main.dart、app.dart。
3. iOS 采用原生 APNs MethodChannel；Android 可用极光官方依赖或原生集成，新增依赖需实际查官方文档。可以编辑 pubspec.yaml，但不要运行 Flutter 命令（主线程在构建）。
4. Android release 必须从被忽略的安全配置读取签名，缺失时报错，禁止 fallback debug。写配置样例与 docs/native-status.md。
5. Apple 开发团队、域名、密钥尚未提供，不能默认使用模板探测的团队进行发布。模拟器无签名验证，真实推送留清晰配置入口。

root已添加 http_parser/cupertino_ui，data完成。不再修改data。所有消息可能被网关隐藏，请在本任务文件和 native-status.md 中交换接口。完成后最终回复可被读取。

补充：iOS 构建经 scripts/flutter.sh 解决了 native hook 的 DEVELOPER_DIR 被过滤问题。不要全局改 xcode-select。当前 root 正在 Android build，完成后会串行重试 iOS。同时两个平台 build 会改同一份生成的插件依赖文件，不要并发。

媒体缺口：media仅接受JPEG/PNG，相册HEIC需在客户端导出JPEG并保留真实拍摄EXIF；没有EXIF时可以用照片库原始asset creation date，但不可用image_picker临时文件生成时间。请判断系统picker是否已转换，写在状态中，必要时实现原生取元数据。

13:54 root构建状态：Android首次构建在你编辑期间编译 Kotlin 报 cn.jpush.* 未找到（Gradle配置在文件修改前已加载）。我会等你完成 native-status.md 再串行重新构建。iOS也等你写完AppDelegate。请完成后写状态即可。
