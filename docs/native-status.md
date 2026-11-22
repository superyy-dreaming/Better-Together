# 原生配置与推送接入

## 已接入的接口

`app/lib/platform/push_service.dart` 提供：

```dart
final push = PushService();
await push.start(repository, (payload) {
  // kind / target_id 来自推送。只映射到应用内允许的路由，不能执行任意 URL。
  // report -> /reports；challenge/comment/like -> /memo/{target_id}；其他 -> /notifications。
});
// 在设置页由用户主动点击“开启系统通知”调用；不在启动时自动弹窗。
await push.requestPermission();
// 用 ValueListenableBuilder 监听 push.state，显示具体状态/错误。
// 必须在 repository.signOut() 前调用，避免残留账号与设备绑定。
await push.stop();
await repository.signOut();
// AppState dispose 时调用，释放本地 listener。
await push.dispose();
```

- `app.dart` 已接入通知启动与目标路由；设置页提供主动开启入口和实时状态。
- 账号登录和 App 恢复前台时重新注册；token 不写日志或持久化到 Dart 存储。
- `PushStatus` 明确区分未授权、注册中、可用与暂不可用。推送异常不清空应用内通知。
- Demo 不初始化任何远程推送 SDK。
- 新增 `unregister_device` 后端接口需求已写 `backend-coordination.md`。

## 已实施

- iOS 相机、照片读取/保存用途；显示名 Better Together；`bettertogether` URL scheme。
- iOS Apple 登录 entitlement、APNs entitlement；Debug development、Release/Profile production。
- iOS 原生 MethodChannel 注册 APNs、返回 token、权限结果、注册错误与通知点击事件；通知内容不写日志。
- Android INTERNET、通知权限、相机用途、相机非必需；显示名 Better Together。
- Android `bettertogether://auth/callback` 与 `bettertogether://invite/...` intent filters。
- Android 使用极光原生 SDK `jpush:6.3.1`、`jcore:5.6.0`，版本来自官方 Flutter 3.6.3 包内 Android 配置。没有引入 iOS 极光 SDK，也没有新增 Flutter 包依赖。
- Android 原生通知权限、注册回调、通知点击冷/热启动与 MethodChannel。
- Android 合并规则移除 SDK 可选定位、电话状态、全部应用查询及旧存储权限，保留通知所需网络权限。
- Android release 仅使用被忽略的 `android/key.properties`，配置缺失或 keystore 不存在即报错，无 debug 签名替代。
- 移除 Xcode 模板自动探测的 DEVELOPMENT_TEAM；可选本地 `Signing.local.xcconfig` 注入明确选择的 Team ID 和 Bundle ID。

## 安全配置

- `config/android-key.example.properties` -> `app/android/key.properties`。
- `config/android-push.example.properties` -> `app/android/push.properties`。
- `config/ios-signing.example.xcconfig` -> `app/ios/Flutter/Signing.local.xcconfig`。
- 这些目标配置以及证书、keystore、p8 均已在 `.gitignore` 排除。极光 master secret 和 APNs p8 只保存在服务端。
- Supabase Auth redirect allow-list 需加入 `bettertogether://auth/callback`；Apple App ID 开启 Sign in with Apple 和 Push Notifications。
- Android 13+ 请求 POST_NOTIFICATIONS；更旧系统也仅在用户点击开启后初始化极光。拒绝权限时只保留应用内通知。
- 未配置真实域名，因此未虚构 Universal Links/Android App Links 域名和关联文件。当前私测使用 custom scheme；未来 HTTPS 邀请需补 AASA、assetlinks 与 entitlement。

## 链接与环境

- AppLinks 已处理 scheme invite 的 host/path 转换：`bettertogether://invite/TOKEN` 转 `/invite?token=TOKEN`。Auth callback 交由 Supabase 处理。
- 设置页已显示 `push.state` 并提供明确开启按钮；真实权限弹窗及送达仍需真机验证。
- 后端 APNs environment 必须与构建匹配：Simulator/Debug 开发环境与 TestFlight production 不可混发。

## 验证与待完成

- `dart analyze app/lib/platform` 无问题；Swift `-typecheck` 对 AppDelegate 成功（完整 Xcode iOS Simulator SDK + Flutter framework）；plist、entitlements、pbxproj 与 Android manifest 语法通过。
- 已下载官方 JPush/JCore AAR，使用 `javap` 核验当前调用的注册、通知、授权 API 签名。
- 按任务要求本代理不运行 Flutter 命令，避免与主线程构建互斥。**原生文件已完成，主线程现在可以串行重新构建两端。**
- 真实 APNs/极光投递、Apple 登录、真机权限、通知冷启动仍需用户安全配置后烟测，不能声称完成。

## HEIC 与照片时间证据

- 实际核验本机 `image_picker_ios 0.8.13+15` Swift 实现：PHPicker 读取原始 data；`saveImageWithOriginalImageData` 对 HEIC/其他格式输出 JPEG，并把原始 ImageIO metadata 写回。当前 UI 已传 `requestFullMetadata:true` 且不缩放，iOS HEIC 无需再次重编码。
- Android 新增 `preparePickedPhoto(path)`，位置 `app/lib/platform/photo_preparation.dart`。JPEG/PNG 保留原字节；其他格式通过原生 Bitmap 解码导出 JPEG，复制 DateTimeOriginal/DateTimeDigitized/OffsetTime/Orientation，**不使用缓存文件生成时间**，不复制 GPS 标签。只接受选择器缓存路径，40MP/20MB 边界显式报错。
- 打卡与头像选择后均已调用 `preparePickedPhoto(file.path)`；DraftPhoto 保存 prepared.bytes / filename / contentType，提交 PhotoUpload 对应字段。
- EXIF 缺失时不造日期，交给现有服务端逐张拒绝（截图仍走 OCR）。当前 picker 不公开 PHAsset ID，无法可靠从它的缓存路径反查 creationDate，因此未添加伪 asset 时间兜底。以原始照片 EXIF 验证仍符合当前 MVP 必需规则。

## 依据

- [Apple APNs 官方文档](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns.md)：每次启动获取 token、不缓存 token、服务端绑定、注册失败独立处理。
- [极光官方 Flutter 插件](https://pub.dev/packages/jpush_flutter/versions/3.6.3)：实际下载核验 3.6.3 archive 的 SDK 依赖、注册/点击 API 与 MIT License；原生 SDK 商用条款需随供应商账号配置确认。
- [Android notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)。
