import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let imageStudioBridge = ImageStudioBridge()
    let imageStudioChannel = FlutterMethodChannel(
      name: "local_ai_chat/image_studio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    imageStudioChannel.setMethodCallHandler { call, result in
      imageStudioBridge.handle(call, result: result)
    }
    let mediaChannel = FlutterMethodChannel(
      name: "local_ai_chat/media",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    mediaChannel.setMethodCallHandler { call, result in
      guard call.method == "prepareImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: String],
            let source = arguments["source"],
            let destination = arguments["destination"],
            let image = UIImage(contentsOfFile: source) else {
        result(FlutterError(code: "image_decode", message: "iPhone could not open this photo.", details: nil))
        return
      }
      let longestSide = max(image.size.width, image.size.height)
      let requestedSide = Double(arguments["maxSide"] ?? "") ?? 1024.0
      let maxSide = min(1536.0, max(320.0, requestedSide))
      let scale = min(1.0, maxSide / max(longestSide, 1.0))
      let target = CGSize(width: max(1, image.size.width * scale),
                          height: max(1, image.size.height * scale))
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
      }
      guard let jpeg = rendered.jpegData(compressionQuality: 0.88) else {
        result(FlutterError(code: "image_encode", message: "iPhone could not convert this photo to JPEG.", details: nil))
        return
      }
      do {
        try jpeg.write(to: URL(fileURLWithPath: destination), options: .atomic)
        result(destination)
      } catch {
        result(FlutterError(code: "image_write", message: "Could not save the converted photo: \(error.localizedDescription)", details: nil))
      }
    }
  }
}
