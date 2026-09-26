import CoreGraphics
import CoreML
import Flutter
import StableDiffusion
import UIKit

/// Runs image-to-image entirely on the phone. A new PNG is written for each edit.
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
        options.startingImage = photo
        options.strength = Float(min(max(strength, 0.05), 0.95))
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
        guard let png = UIImage(cgImage: image).pngData() else {
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
}

private enum ImageStudioError: LocalizedError {
  case cannotDecode
  case cannotEncode
  case cancelledOrEmpty

  var errorDescription: String? {
    switch self {
    case .cannotDecode: return "Could not open the chosen photo."
    case .cannotEncode: return "Could not save the edited photo."
    case .cancelledOrEmpty: return "Image edit stopped before a result was ready."
    }
  }
}
