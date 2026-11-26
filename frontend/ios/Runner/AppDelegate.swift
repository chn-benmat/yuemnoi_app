import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let foregroundNotifications = ForegroundNotificationDelegate()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = foregroundNotifications
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    foregroundNotifications.channel = FlutterMethodChannel(
      name: "yuemnoi/foreground_notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  var channel: FlutterMethodChannel?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let data = notification.request.content.userInfo
    guard notification.request.trigger is UNPushNotificationTrigger,
          let category = data["category"] as? String,
          let recipient = data["recipient_id"] as? String,
          category == "rental" || category == "app" else {
      completionHandler([])
      return
    }
    var arguments = ["category": category, "recipient_id": recipient]
    arguments["expires_at"] = data["expires_at"] as? String
    DispatchQueue.main.async { [weak self, arguments] in
      guard let channel = self?.channel else {
        completionHandler([])
        return
      }
      // ตรวจบัญชีปัจจุบันก่อนแสดง และจบ callback แม้ Flutter ยังไม่พร้อม
      var completed = false
      let finish: (UNNotificationPresentationOptions) -> Void = { options in
        guard !completed else { return }
        completed = true
        completionHandler(options)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { finish([]) }
      channel.invokeMethod("shouldPresent", arguments: arguments) { result in
        guard result as? Bool == true else {
          finish([])
          return
        }
        if #available(iOS 14.0, *) {
          finish([.banner, .list, .sound])
        } else {
          finish([.alert, .sound])
        }
      }
    }
  }
}
