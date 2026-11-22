import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var currentToken: String?
  private var pendingOpen: [String: String]?
  private var pushStarted = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Explicit CLI-only benchmark launch. Normal launches keep system defaults.
    // Prevent auto-lock from suspending timed foreground recognition runs.
    if ProcessInfo.processInfo.arguments.contains("--ai-benchmark-keep-awake") {
      application.isIdleTimerDisabled = true
    }
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BetterTogetherPush") else { return }
    let channel = FlutterMethodChannel(name: "better_together/push", binaryMessenger: registrar.messenger())
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "start":
        self.pushStarted = true
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            result(["status": allowed ? "authorized" : "not_authorized", "token": self.currentToken ?? ""])
            if let payload = self.pendingOpen { self.pushChannel?.invokeMethod("open", arguments: payload); self.pendingOpen = nil }
          }
        }
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { allowed, error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "permission_error", message: error.localizedDescription, details: nil)); return }
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            result(allowed)
          }
        }
      case "stop":
        self.pushStarted = false
        UIApplication.shared.unregisterForRemoteNotifications()
        self.currentToken = nil
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    currentToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    if pushStarted { pushChannel?.invokeMethod("token", arguments: currentToken) }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    pushChannel?.invokeMethod("registrationError", arguments: "设备尚未注册远程通知，请稍后重试")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    let payload = ["kind": info["kind"] as? String ?? "", "target_id": info["target_id"] as? String ?? ""]
    if pushStarted { pushChannel?.invokeMethod("open", arguments: payload) }
    else { pendingOpen = payload }
    completionHandler()
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }
}
