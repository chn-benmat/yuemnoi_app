import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "yuemnoi/identity_card_photo",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "prepare" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String, !path.isEmpty,
        let preview = arguments["previewAspectRatio"] as? Double, preview.isFinite, preview > 0,
        let card = arguments["cardAspectRatio"] as? Double, card.isFinite, card > 0
      else {
        result(FlutterError(code: "invalid_photo", message: "Invalid card photo arguments", details: nil))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let jpeg = prepareCardPhoto(path: path, preview: CGFloat(preview), card: CGFloat(card))
        DispatchQueue.main.async {
          if let jpeg {
            result(FlutterStandardTypedData(bytes: jpeg))
          } else {
            result(FlutterError(code: "invalid_photo", message: "Cannot prepare card photo", details: nil))
          }
        }
      }
    }
  }
}

private func prepareCardPhoto(path: String, preview: CGFloat, card: CGFloat) -> Data? {
  guard let image = UIImage(contentsOfFile: path),
    image.size.width > 0, image.size.height > 0
  else { return nil }

  // เทียบพื้นที่กลางของภาพถ่ายกับพรีวิว และวาดเฉพาะภาพในกรอบลง JPEG
  let previewWidth = min(image.size.width, image.size.height * preview)
  let cropWidth = min(previewWidth, previewWidth / preview * card)
  let width = max(1, min(1800, (cropWidth * image.scale).rounded()))
  let height = max(1, (width / card).rounded())
  let scale = width / cropWidth
  let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = true
  let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
  return renderer.jpegData(withCompressionQuality: 0.9) { _ in
    image.draw(in: CGRect(
      x: (width - drawn.width) / 2,
      y: (height - drawn.height) / 2,
      width: drawn.width,
      height: drawn.height))
  }
}
