import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Flutter
import StableDiffusion
import UIKit
import Vision

/// Runs local image generation and person-preserving compositing on the phone.
final class ImageStudioBridge {
  private let editStageKey = "FluxLiraImageStudioLastStage"
  private let lock = NSLock()
  private var busy = false
  private var cancelled = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "lastEditStage" {
      result(UserDefaults.standard.string(forKey: editStageKey))
      return
    }
    if call.method == "cancelEdit" {
      lock.lock()
      cancelled = true
      lock.unlock()
      result(nil)
      return
    }
    if call.method == "verifyModel" {
      guard #available(iOS 17.0, *),
            let args = call.arguments as? [String: Any],
            let resources = args["modelDirectory"] as? String else {
        result(FlutterError(code: "model_input", message: "Choose an iPhone Core ML image model.", details: nil))
        return
      }
      lock.lock()
      let alreadyBusy = busy
      if !alreadyBusy { busy = true }
      lock.unlock()
      if alreadyBusy {
        result(FlutterError(code: "edit_busy", message: "Wait for the current image operation to finish.", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        do {
          let config = MLModelConfiguration()
          config.computeUnits = .cpuAndNeuralEngine
          let pipeline = try StableDiffusionPipeline(
            resourcesAt: URL(fileURLWithPath: resources, isDirectory: true),
            controlNet: [], configuration: config,
            disableSafety: true, reduceMemory: true
          )
          try pipeline.loadResources()
          pipeline.unloadResources()
          finish(result, value: true)
        } catch {
          finish(result, error: FlutterError(code: "model_invalid", message: "This model cannot load on this iPhone: \(error.localizedDescription)", details: nil))
        }
      }
      return
    }
    guard call.method == "editImage" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard #available(iOS 17.0, *) else {
      result(FlutterError(code: "ios_version", message: "Local image editing needs iOS 17 or newer.", details: nil))
      return
    }
    guard let args = call.arguments as? [String: Any],
          let input = args["input"] as? String,
          let output = args["output"] as? String,
          let resources = args["modelDirectory"] as? String,
          let prompt = args["prompt"] as? String,
          let strength = args["strength"] as? Double,
          let steps = args["steps"] as? Int,
          let seed = args["seed"] as? Int,
          !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(code: "edit_input", message: "Choose a photo and describe an edit.", details: nil))
      return
    }
    lock.lock()
    let alreadyBusy = busy
    if !alreadyBusy {
      busy = true
      cancelled = false
    }
    lock.unlock()
    if alreadyBusy {
      result(FlutterError(code: "edit_busy", message: "An image edit is already running.", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      do {
        UserDefaults.standard.set("preparing photo", forKey: editStageKey)
        let photo = try loadSquareImage(at: input)
        guard !isCancelled() else { throw ImageStudioError.cancelledOrEmpty }
        UserDefaults.standard.set("loading image model", forKey: editStageKey)
        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .cpuAndNeuralEngine
        let pipeline = try StableDiffusionPipeline(
          resourcesAt: URL(fileURLWithPath: resources, isDirectory: true),
          controlNet: [],
          configuration: mlConfig,
          disableSafety: true,
          reduceMemory: true
        )
        defer { pipeline.unloadResources() }
        // With reduceMemory enabled, generation loads each component only
        // when it is needed. Prewarming every model here can create a large
        // memory spike before the first diffusion step on an iPhone.
        var options = StableDiffusionPipeline.Configuration(prompt: prompt)
        options.startingImage = photo
        options.strength = Float(min(max(strength, 0.05), 0.95))
        options.stepCount = min(max(steps, 8), 40)
        options.seed = UInt32(clamping: seed)
        options.guidanceScale = 7.0
        options.disableSafety = true
        UserDefaults.standard.set("generating image", forKey: editStageKey)
        let images = try pipeline.generateImages(
          configuration: options,
          progressHandler: { _ in !self.isCancelled() }
        )
        guard let image = images.first ?? nil else {
          throw ImageStudioError.cancelledOrEmpty
        }
        guard !isCancelled() else { throw ImageStudioError.cancelledOrEmpty }
        let edited = image
        guard !isCancelled() else { throw ImageStudioError.cancelledOrEmpty }
        guard let png = UIImage(cgImage: edited).pngData() else {
          throw ImageStudioError.cannotEncode
        }
        UserDefaults.standard.set("saving image", forKey: editStageKey)
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
        UserDefaults.standard.removeObject(forKey: editStageKey)
        finish(result, value: output)
      } catch {
        UserDefaults.standard.removeObject(forKey: editStageKey)
        finish(result, error: FlutterError(
          code: isCancelled() ? "edit_cancelled" : "edit_failed",
          message: isCancelled() ? "Image edit stopped." : error.localizedDescription,
          details: nil
        ))
      }
    }
  }

  private func isCancelled() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  private func finish(_ result: @escaping FlutterResult, value: Any? = nil, error: FlutterError? = nil) {
    lock.lock()
    busy = false
    lock.unlock()
    DispatchQueue.main.async { result(error ?? value) }
  }

  private func loadSquareImage(at path: String) throws -> CGImage {
    guard let source = UIImage(contentsOfFile: path) else {
      throw ImageStudioError.cannotDecode
    }
    let fittedWidth = source.size.width * 512 / max(source.size.width, source.size.height)
    let fittedHeight = source.size.height * 512 / max(source.size.width, source.size.height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
      UIColor(red: 32 / 255, green: 32 / 255, blue: 32 / 255, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
      source.draw(in: CGRect(x: (512 - fittedWidth) / 2,
                           y: (512 - fittedHeight) / 2,
                           width: fittedWidth,
                           height: fittedHeight))
    }
    guard let image = rendered.cgImage else { throw ImageStudioError.cannotDecode }
    return image
  }

  /// The foreground-instance model follows the complete visible subject.
  /// The older person model is used only to identify which instance is human;
  /// its truncated matte is never used for the final composite.
  @available(iOS 17.0, *)
  private func makeSubjectMask(for photo: CGImage) throws -> CIImage {
    let handler = VNImageRequestHandler(cgImage: photo, options: [:])
    let personRequest = VNGeneratePersonSegmentationRequest()
    personRequest.qualityLevel = .accurate
    personRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let foregroundRequest = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([personRequest, foregroundRequest])
    guard let person = personRequest.results?.first?.pixelBuffer,
          let observation = foregroundRequest.results?.first,
          let selected = matchingForegroundInstance(
            person: person, instances: observation.instanceMask
          ), observation.allInstances.contains(selected) else {
      throw ImageStudioError.personNotFound
    }
    let instanceBuffer = observation.instanceMask
    let coverage = instanceCoverage(instanceBuffer, label: selected)
    guard coverage > 0.01, coverage < 0.75,
          !hasAbruptSubjectCutoff(instanceBuffer, label: selected) else {
      throw ImageStudioError.personNotFound
    }
    let buffer = try observation.generateScaledMaskForImage(
      forInstances: IndexSet(integer: selected), from: handler
    )
    return CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(
      scaleX: CGFloat(photo.width) / CGFloat(CVPixelBufferGetWidth(buffer)),
      y: CGFloat(photo.height) / CGFloat(CVPixelBufferGetHeight(buffer))
    ))
  }

  private func matchingForegroundInstance(person: CVPixelBuffer,
                                          instances: CVPixelBuffer) -> Int? {
    guard CVPixelBufferGetPixelFormatType(person) == kCVPixelFormatType_OneComponent8,
          CVPixelBufferGetPixelFormatType(instances) == kCVPixelFormatType_OneComponent8 else {
      return nil
    }
    CVPixelBufferLockBaseAddress(person, .readOnly)
    CVPixelBufferLockBaseAddress(instances, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(instances, .readOnly)
      CVPixelBufferUnlockBaseAddress(person, .readOnly)
    }
    guard let personBase = CVPixelBufferGetBaseAddress(person),
          let instanceBase = CVPixelBufferGetBaseAddress(instances) else { return nil }
    let personPixels = personBase.assumingMemoryBound(to: UInt8.self)
    let instancePixels = instanceBase.assumingMemoryBound(to: UInt8.self)
    let pw = CVPixelBufferGetWidth(person)
    let ph = CVPixelBufferGetHeight(person)
    let iw = CVPixelBufferGetWidth(instances)
    let ih = CVPixelBufferGetHeight(instances)
    let personRow = CVPixelBufferGetBytesPerRow(person)
    let instanceRow = CVPixelBufferGetBytesPerRow(instances)
    var hits = [Int: Int]()
    var personSamples = 0
    for y in stride(from: 0, to: ph, by: max(1, ph / 128)) {
      for x in stride(from: 0, to: pw, by: max(1, pw / 128)) {
        guard personPixels[y * personRow + x] > 128 else { continue }
        personSamples += 1
        let label = Int(instancePixels[(y * ih / ph) * instanceRow + (x * iw / pw)])
        if label != 0 { hits[label, default: 0] += 1 }
      }
    }
    guard let winner = hits.max(by: { $0.value < $1.value }),
          winner.value >= max(12, personSamples / 3) else { return nil }
    return winner.key
  }

  private func instanceCoverage(_ buffer: CVPixelBuffer, label: Int) -> Double {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else {
      return 0
    }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
    let pixels = base.assumingMemoryBound(to: UInt8.self)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    var covered = 0
    var sampled = 0
    for y in stride(from: 0, to: height, by: max(1, height / 128)) {
      for x in stride(from: 0, to: width, by: max(1, width / 128)) {
        sampled += 1
        if Int(pixels[y * row + x]) == label { covered += 1 }
      }
    }
    return Double(covered) / Double(max(1, sampled))
  }

  /// A broad, flat end in the middle of a portrait usually means the matte
  /// dropped the rest of the body. Stop before spending time generating scenery.
  private func hasAbruptSubjectCutoff(_ buffer: CVPixelBuffer, label: Int) -> Bool {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else {
      return true
    }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return true }
    let pixels = base.assumingMemoryBound(to: UInt8.self)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    var rowWidths = [Int](repeating: 0, count: height)
    for y in 0..<height {
      for x in 0..<width where Int(pixels[y * row + x]) == label {
        rowWidths[y] += 1
      }
    }
    guard let first = rowWidths.firstIndex(where: { $0 > 0 }),
          let last = rowWidths.lastIndex(where: { $0 > 0 }) else { return true }
    let end = Array(rowWidths[max(first, last - 3)...last])
    let endWidth = Double(end.reduce(0, +)) / Double(max(1, end.count * width))
    return last < Int(Double(height) * 0.80) &&
      first < Int(Double(height) * 0.35) && endWidth > 0.20
  }

  private func composite(original: CGImage, background: CGImage,
                         subjectMask: CIImage) throws -> CGImage {
    let filter = CIFilter.blendWithMask()
    filter.inputImage = CIImage(cgImage: original)
    filter.backgroundImage = CIImage(cgImage: background)
    filter.maskImage = subjectMask
    guard let result = filter.outputImage,
          let rendered = CIContext().createCGImage(
            result, from: CGRect(x: 0, y: 0,
                                 width: CGFloat(original.width),
                                 height: CGFloat(original.height))
          ) else {
      throw ImageStudioError.cannotEncode
    }
    return rendered
  }
}

private enum ImageStudioError: LocalizedError {
  case cannotDecode
  case cannotEncode
  case cancelledOrEmpty
  case personNotFound

  var errorDescription: String? {
    switch self {
    case .cannotDecode: return "Could not open the chosen photo."
    case .cannotEncode: return "Could not save the edited photo."
    case .cancelledOrEmpty: return "Image edit stopped before a result was ready."
    case .personNotFound: return "Could not keep the complete subject in this photo. Try a clearer photo with the whole subject in view. Your original is unchanged."
    }
  }
}
