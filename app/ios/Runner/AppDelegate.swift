import Flutter
import UIKit
import AVFoundation

// When the larger Kokoro model cannot allocate on iPhone, use an installed
// iOS voice so an otherwise successful chat reply still speaks out loud.
final class SystemSpeechBridge: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var pending: FlutterResult?
  private var activeUtterance: AVSpeechUtterance?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      guard let arguments = call.arguments as? [String: Any],
            let text = arguments["text"] as? String,
            !text.isEmpty else {
        result(FlutterError(code: "speech_text", message: "There is no text to speak.", details: nil))
        return
      }
      let previous = pending
      pending = nil
      activeUtterance = nil
      if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
      previous?(nil)
      pending = result
      let voiceId = arguments["voice"] as? Int ?? 5
      let utterance = AVSpeechUtterance(string: text)
      let english = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .sorted { $0.identifier < $1.identifier }
      let female = english.filter { $0.gender == .female }
      let male = english.filter { $0.gender == .male }
      let isFemale = voiceId == 1 || voiceId == 7
      let preferred = isFemale ? female : male
      let index = switch voiceId {
      case 6, 7: 1
      case 9: 2
      default: 0
      }
      utterance.voice = preferred.isEmpty
        ? (english.first ?? AVSpeechSynthesisVoice(language: "en-US"))
        : preferred[index % preferred.count]
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      activeUtterance = utterance
      synthesizer.speak(utterance)
    case "stop":
      let previous = pending
      pending = nil
      activeUtterance = nil
      if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
      previous?(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                         didFinish utterance: AVSpeechUtterance) {
    guard utterance === activeUtterance else { return }
    pending?(nil)
    pending = nil
    activeUtterance = nil
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                         didCancel utterance: AVSpeechUtterance) {
    guard utterance === activeUtterance else { return }
    pending?(nil)
    pending = nil
    activeUtterance = nil
  }
}

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
    let systemSpeechBridge = SystemSpeechBridge()
    let speechChannel = FlutterMethodChannel(
      name: "local_ai_chat/system_speech",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    speechChannel.setMethodCallHandler { call, result in
      systemSpeechBridge.handle(call, result: result)
    }
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
