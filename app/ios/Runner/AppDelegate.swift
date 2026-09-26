import Flutter
import UIKit
import AVFoundation

private struct ModelTransferRecord: Codable {
  var id: String
  var url: String
  var destination: String
  var state: String
  var received: Int64
  var expected: Int64
  var error: String?

  var dictionary: [String: Any] {
    ["id": id, "state": state, "received": received,
     "expected": expected, "error": error ?? ""]
  }
}

/// iOS owns these transfers so they can continue while Flutter is suspended.
final class ModelTransferBridge: NSObject, URLSessionDownloadDelegate {
  static let sessionIdentifier = "com.localai.localAiChat.modelTransfers"
  private let storageKey = "modelTransferRecordsV1"
  private var records = [String: ModelTransferRecord]()
  private var backgroundCompletion: (() -> Void)?
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.sessionIdentifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: storageKey),
       let saved = try? JSONDecoder().decode([String: ModelTransferRecord].self, from: data) {
      records = saved
    }
    _ = session
  }

  func setBackgroundCompletion(_ completion: @escaping () -> Void) {
    synchronized { backgroundCompletion = completion }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String,
            let source = args["url"] as? String,
            let url = URL(string: source), url.scheme == "https",
            let destination = args["destination"] as? String,
            id.range(of: "^[A-Za-z0-9._-]{1,160}$", options: .regularExpression) != nil,
            destination.hasSuffix(".part") else {
        result(FlutterError(code: "download_input", message: "Invalid model download.", details: nil))
        return
      }
      let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!.standardizedFileURL.path
      let target = URL(fileURLWithPath: destination).standardizedFileURL.path
      guard target.hasPrefix(root + "/") else {
        result(FlutterError(code: "download_path", message: "Model must be saved in the app.", details: nil))
        return
      }
      let alreadyStarted = synchronized { () -> Bool in
        if let existing = records[id],
           existing.state == "downloading" || existing.state == "downloaded" {
          return true
        }
        records[id] = ModelTransferRecord(id: id, url: source,
          destination: target, state: "downloading", received: 0,
          expected: (args["expected"] as? NSNumber)?.int64Value ?? 0,
          error: nil)
        persist()
        return false
      }
      if !alreadyStarted {
        let task = session.downloadTask(with: url)
        task.taskDescription = id
        task.resume()
      }
      result(nil)
    case "list":
      session.getAllTasks { [weak self] tasks in
        guard let self else { return }
        let values = self.synchronized { () -> [[String: Any]] in
          self.records.values.sorted { $0.id < $1.id }.map { record in
            var value = record.dictionary
            if let task = tasks.first(where: { $0.taskDescription == record.id }),
               record.state == "downloading" {
              value["received"] = max(0, task.countOfBytesReceived)
              if task.countOfBytesExpectedToReceive > 0 {
                value["expected"] = task.countOfBytesExpectedToReceive
              }
            }
            return value
          }
        }
        DispatchQueue.main.async { result(values) }
      }
    case "cancel":
      guard let id = (call.arguments as? [String: Any])?["id"] as? String else {
        result(FlutterError(code: "download_input", message: "Missing download ID.", details: nil))
        return
      }
      session.getAllTasks { [weak self] tasks in
        tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        self?.update(id) { $0.state = "cancelled" }
        DispatchQueue.main.async { result(nil) }
      }
    case "forget":
      guard let id = (call.arguments as? [String: Any])?["id"] as? String else {
        result(FlutterError(code: "download_input", message: "Missing download ID.", details: nil))
        return
      }
      synchronized { records.removeValue(forKey: id); persist() }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard let id = downloadTask.taskDescription else { return }
    guard let response = downloadTask.response as? HTTPURLResponse,
          (200...299).contains(response.statusCode) else {
      update(id) { $0.state = "failed"; $0.error = "Server rejected the download." }
      return
    }
    guard let destination = synchronized({ records[id]?.destination }) else { return }
    do {
      let target = URL(fileURLWithPath: destination)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.moveItem(at: location, to: target)
      let bytes = (try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
      update(id) { $0.state = "downloaded"; $0.received = bytes; $0.error = nil }
    } catch {
      update(id) { $0.state = "failed"; $0.error = error.localizedDescription }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    guard let id = task.taskDescription, let error else { return }
    update(id) {
      if $0.state != "downloaded" && $0.state != "cancelled" {
        $0.state = "failed"
        $0.error = error.localizedDescription
      }
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    let completion = synchronized { () -> (() -> Void)? in
      let pending = backgroundCompletion
      backgroundCompletion = nil
      return pending
    }
    if let completion { DispatchQueue.main.async(execute: completion) }
  }

  private func update(_ id: String, change: (inout ModelTransferRecord) -> Void) {
    synchronized {
      guard var record = records[id] else { return }
      change(&record)
      records[id] = record
      persist()
    }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(records) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }

  private let lock = NSRecursiveLock()
  private func synchronized<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

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
  private let modelTransfers = ModelTransferBridge()

  override func application(_ application: UIApplication,
                            handleEventsForBackgroundURLSession identifier: String,
                            completionHandler: @escaping () -> Void) {
    if identifier == ModelTransferBridge.sessionIdentifier {
      modelTransfers.setBackgroundCompletion(completionHandler)
    } else {
      completionHandler()
    }
  }
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
    let transferChannel = FlutterMethodChannel(
      name: "local_ai_chat/model_transfers",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    transferChannel.setMethodCallHandler { [modelTransfers = self.modelTransfers] call, result in
      modelTransfers.handle(call, result: result)
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
