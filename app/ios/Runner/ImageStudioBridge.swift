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
  private let lock = NSLock()
  private var busy = false
  private var cancelled = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "cancelEdit" {
      lock.lock()
      cancelled = true
      lock.unlock()
      result(nil)
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
          let backgroundOnly = args["backgroundOnly"] as? Bool,
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
        let photo = try loadSquareImage(at: input)
        let personMask = backgroundOnly ? try makePersonMask(for: photo) : nil
        guard !isCancelled() else { throw ImageStudioError.cancelledOrEmpty }
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
        try pipeline.loadResources()
        var options = StableDiffusionPipeline.Configuration(prompt: prompt)
        if backgroundOnly {
          options.negativePrompt = "person, people, human, portrait, face, body"
        } else {
          options.startingImage = photo
          options.strength = Float(min(max(strength, 0.05), 0.95))
        }
        options.stepCount = min(max(steps, 8), 40)
        options.seed = UInt32(clamping: seed)
        options.guidanceScale = 7.0
        options.disableSafety = true
        let images = try pipeline.generateImages(
          configuration: options,
          progressHandler: { _ in !self.isCancelled() }
        )
        guard let image = images.first ?? nil else {
          throw ImageStudioError.cancelledOrEmpty
        }
        guard !isCancelled() else { throw ImageStudioError.cancelledOrEmpty }
        let edited: CGImage
        if let personMask {
          edited = try composite(
            original: photo,
            background: image,
            personMask: personMask
          )
        } else {
          edited = image
        }
        guard !isCancelled() else { throw ImageStudioError.cancelledOrEmpty }
        guard let png = UIImage(cgImage: edited).pngData() else {
          throw ImageStudioError.cannotEncode
        }
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
        finish(result, value: output)
      } catch {
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

  private func finish(_ result: @escaping FlutterResult, value: String? = nil, error: FlutterError? = nil) {
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

  /// Vision supplies a matte of the original person. A missing or nearly
  /// full-frame matte is rejected so a generated stranger is never shown.
  private func makePersonMask(for photo: CGImage) throws -> CIImage {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try VNImageRequestHandler(cgImage: photo, options: [:]).perform([request])
    guard let buffer = request.results?.first?.pixelBuffer else {
      throw ImageStudioError.personNotFound
    }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw ImageStudioError.personNotFound
    }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let pixels = base.assumingMemoryBound(to: UInt8.self)
    let stepX = max(1, width / 64)
    let stepY = max(1, height / 64)
    var sampled = 0
    var covered = 0
    for y in stride(from: 0, to: height, by: stepY) {
      for x in stride(from: 0, to: width, by: stepX) {
        sampled += 1
        if pixels[y * rowBytes + x] > 128 { covered += 1 }
      }
    }
    let coverage = Double(covered) / Double(max(1, sampled))
    guard coverage > 0.005 && coverage < 0.95 else {
      throw ImageStudioError.personNotFound
    }
    return CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(
      scaleX: CGFloat(photo.width) / CGFloat(width),
      y: CGFloat(photo.height) / CGFloat(height)
    ))
  }

  private func composite(original: CGImage, background: CGImage,
                         personMask: CIImage) throws -> CGImage {
    let filter = CIFilter.blendWithMask()
    filter.inputImage = CIImage(cgImage: original)
    filter.backgroundImage = CIImage(cgImage: background)
    filter.maskImage = personMask
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
    case .personNotFound: return "Could not separate a person from this photo. Try a clearer photo with the person in view. Your original is unchanged."
    }
  }
}
