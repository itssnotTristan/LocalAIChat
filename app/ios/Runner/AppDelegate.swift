import Flutter
import UIKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

/// PHPicker lets the user choose individual photos and videos without granting
/// this app access to their entire library.
final class PhotoPickerBridge: NSObject, PHPickerViewControllerDelegate {
  private var pending: FlutterResult?
  private var picker: PHPickerViewController?
  private var requestedType = "image"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "pick" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pending == nil else {
      result(FlutterError(code: "picker_busy", message: "Finish choosing the current item first.", details: nil))
      return
    }
    requestedType = (call.arguments as? [String: String])?["type"] == "video" ? "video" : "image"
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.selectionLimit = 1
    configuration.filter = requestedType == "video" ? .videos : .images
    configuration.preferredAssetRepresentationMode = .current
    let newPicker = PHPickerViewController(configuration: configuration)
    newPicker.delegate = self
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "picker_unavailable", message: "Could not open Photos on this iPhone.", details: nil))
      return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    pending = result
    picker = newPicker
    presenter.present(newPicker, animated: true)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else {
      finish(nil)
      return
    }
    let expected: UTType = requestedType == "video" ? .movie : .image
    guard let identifier = provider.registeredTypeIdentifiers.first(where: {
      UTType($0)?.conforms(to: expected) == true
    }) else {
      finish(FlutterError(code: "picker_type", message: "The selected media could not be opened.", details: nil))
      return
    }
    provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
      guard let self = self else { return }
      guard let url = url else {
        DispatchQueue.main.async {
          self.finish(FlutterError(code: "picker_load", message: error?.localizedDescription ?? "Could not load the selected media.", details: nil))
        }
        return
      }
      let fileExtension = url.pathExtension.isEmpty ? (self.requestedType == "video" ? "mov" : "jpg") : url.pathExtension
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("fluxlira-picked-\(UUID().uuidString)")
        .appendingPathExtension(fileExtension)
      do {
        try FileManager.default.copyItem(at: url, to: destination)
        DispatchQueue.main.async { self.finish(destination.path) }
      } catch {
        DispatchQueue.main.async {
          self.finish(FlutterError(code: "picker_copy", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func finish(_ value: Any?) {
    let callback = pending
    pending = nil
    picker = nil
    callback?(value)
  }
}

private struct ModelTransferRecord: Codable {
  var id: String
  var generation: String?
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
  private var activeDescriptions = Set<String>()
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
      let generation = UUID().uuidString
      let alreadyStarted = synchronized { () -> Bool in
        if let existing = records[id],
           existing.state == "downloading" || existing.state == "downloaded" {
          return true
        }
        records[id] = ModelTransferRecord(id: id, generation: generation, url: source,
          destination: target, state: "downloading", received: 0,
          expected: (args["expected"] as? NSNumber)?.int64Value ?? 0,
          error: nil)
        activeDescriptions.insert("\(id)|\(generation)")
        persist()
        return false
      }
      if !alreadyStarted {
        let task = session.downloadTask(with: url)
        task.taskDescription = "\(id)|\(generation)"
        task.resume()
      }
      result(nil)
    case "list":
      session.getAllTasks { [weak self] tasks in
        guard let self else { return }
        let values = self.synchronized { () -> [[String: Any]] in
          let interrupted = self.records.values.filter { record in
            let description = self.description(for: record)
            return record.state == "downloading" &&
              !self.activeDescriptions.contains(description) &&
              !tasks.contains(where: { $0.taskDescription == description })
          }.map { $0.id }
          for id in interrupted {
            self.records[id]?.state = "failed"
            self.records[id]?.error = "Download was interrupted. Tap download to retry."
          }
          if !interrupted.isEmpty { self.persist() }
          return self.records.values.sorted { $0.id < $1.id }.map { record in
            var value = record.dictionary
            if let task = tasks.first(where: {
                 $0.taskDescription == self.description(for: record) }),
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
        guard let self else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        let description = self.synchronized {
          self.records[id].map { self.description(for: $0) }
        }
        tasks.filter { $0.taskDescription == description }.forEach { $0.cancel() }
        if let description {
          self.synchronized { self.activeDescriptions.remove(description) }
        }
        self.update(id) { $0.state = "cancelled" }
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
    guard let (id, generation) = identity(of: downloadTask),
          synchronized({ records[id]?.generation == generation }) else { return }
    guard let response = downloadTask.response as? HTTPURLResponse,
          (200...299).contains(response.statusCode) else {
      update(id, generation: generation, requireGenerationMatch: true) {
        $0.state = "failed"; $0.error = "Server rejected the download." }
      return
    }
    guard let destination = synchronized({
      records[id]?.generation == generation ? records[id]?.destination : nil
    }) else { return }
    do {
      let target = URL(fileURLWithPath: destination)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.moveItem(at: location, to: target)
      let bytes = (try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
      update(id, generation: generation, requireGenerationMatch: true) {
        $0.state = "downloaded"; $0.received = bytes; $0.error = nil }
    } catch {
      update(id, generation: generation, requireGenerationMatch: true) {
        $0.state = "failed"; $0.error = error.localizedDescription }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    if let description = task.taskDescription {
      synchronized { activeDescriptions.remove(description) }
    }
    guard let (id, generation) = identity(of: task), let error else { return }
    update(id, generation: generation, requireGenerationMatch: true) {
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

  private func description(for record: ModelTransferRecord) -> String {
    guard let generation = record.generation else { return record.id }
    return "\(record.id)|\(generation)"
  }

  private func identity(of task: URLSessionTask) -> (String, String?)? {
    guard let description = task.taskDescription else { return nil }
    guard let separator = description.firstIndex(of: "|") else {
      return (description, nil)
    }
    return (String(description[..<separator]),
            String(description[description.index(after: separator)...]))
  }

  private func update(_ id: String, generation: String? = nil,
                      requireGenerationMatch: Bool = false,
                      change: (inout ModelTransferRecord) -> Void) {
    synchronized {
      guard var record = records[id] else { return }
      if requireGenerationMatch && record.generation != generation { return }
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
      let requestedRate = (arguments["rate"] as? NSNumber)?.doubleValue ?? 1.0
      utterance.rate = Float(min(max(requestedRate, 0.8), 1.4)) * AVSpeechUtteranceDefaultSpeechRate
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
  private let photoPicker = PhotoPickerBridge()

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
    let photoChannel = FlutterMethodChannel(
      name: "local_ai_chat/photo_picker",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    photoChannel.setMethodCallHandler { [photoPicker = self.photoPicker] call, result in
      photoPicker.handle(call, result: result)
    }
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
    let appIconChannel = FlutterMethodChannel(
      name: "local_ai_chat/app_icon",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appIconChannel.setMethodCallHandler { call, result in
      DispatchQueue.main.async {
        switch call.method {
        case "supports":
          result(UIApplication.shared.supportsAlternateIcons)
        case "current":
          result(UIApplication.shared.alternateIconName)
        case "set":
          guard UIApplication.shared.supportsAlternateIcons else {
            result(FlutterError(code: "unsupported", message: "This iPhone cannot change the app icon.", details: nil))
            return
          }
          let name = call.arguments as? String
          guard name == nil || name == "AppIconOrange" || name == "AppIconElectric" else {
            result(FlutterError(code: "invalid_icon", message: "Unknown app icon.", details: nil))
            return
          }
          UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
              if let error = error {
                result(FlutterError(code: "icon_change_failed", message: error.localizedDescription, details: nil))
              } else {
                result(nil)
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
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
