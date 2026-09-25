import AVFoundation
import Cocoa
import FlutterMacOS
import QuickLookThumbnailing

public class FlutterVideoThumbnailPlusPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_video_thumbnail_plus",
      binaryMessenger: registrar.messenger)
    let instance = FlutterVideoThumbnailPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Expected map arguments", details: nil))
      return
    }

    guard let video = args["video"] as? String else {
      result(FlutterError(code: "invalid_video", message: "Missing video path", details: nil))
      return
    }

    let headers = args["headers"] as? [String: String]
    let path = args["path"] as? String
    let format = (args["format"] as? NSNumber)?.intValue ?? 0
    let maxh = (args["maxh"] as? NSNumber)?.intValue ?? 0
    let maxw = (args["maxw"] as? NSNumber)?.intValue ?? 0
    let timeMs = (args["timeMs"] as? NSNumber)?.intValue ?? 0
    let quality = (args["quality"] as? NSNumber)?.intValue ?? 10

    let url: URL
    if video.hasPrefix("file://") {
      url = URL(fileURLWithPath: String(video.dropFirst(7)))
    } else if video.hasPrefix("/") {
      url = URL(fileURLWithPath: video)
    } else {
      guard let remoteURL = URL(string: video) else {
        result(FlutterError(code: "invalid_url", message: "Invalid video URL", details: nil))
        return
      }
      url = remoteURL
    }

    DispatchQueue.global(qos: .userInitiated).async {
      var didAccessSecurityScopedResource = false
      if url.isFileURL {
        didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
      }
      defer {
        if didAccessSecurityScopedResource {
          url.stopAccessingSecurityScopedResource()
        }
      }

      switch call.method {
      case "data":
        do {
          let data = try Self.generateThumbnail(
            url: url,
            headers: headers,
            format: format,
            maxHeight: maxh,
            maxWidth: maxw,
            timeMs: timeMs,
            quality: quality)
          result(FlutterStandardTypedData(bytes: data))
        } catch {
          result(FlutterError(code: "thumbnail_error", message: error.localizedDescription, details: nil))
        }
      case "file":
        do {
          let data = try Self.generateThumbnail(
            url: url,
            headers: headers,
            format: format,
            maxHeight: maxh,
            maxWidth: maxw,
            timeMs: timeMs,
            quality: quality)
          let outputPath = try Self.resolveOutputPath(
            originalVideo: video,
            requestedPath: path,
            format: format)
          try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
          result(outputPath)
        } catch {
          result(FlutterError(code: "thumbnail_error", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func resolveOutputPath(
    originalVideo: String,
    requestedPath: String?,
    format: Int
  ) throws -> String {
    let ext = fileExtension(for: format)
    if let requestedPath, !requestedPath.isEmpty {
      if URL(fileURLWithPath: requestedPath).pathExtension.lowercased() == ext {
        return requestedPath
      }

      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: requestedPath, isDirectory: &isDir), isDir.boolValue {
        let fileName = "\(UUID().uuidString).\(ext)"
        return URL(fileURLWithPath: requestedPath).appendingPathComponent(fileName).path
      }

      return requestedPath + "." + ext
    }

    // On macOS sandbox, writing near user-selected files can fail.
    // Save generated thumbnails in app cache by default.
    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return cacheDir.appendingPathComponent("\(UUID().uuidString).\(ext)").path
  }

  private static func fileExtension(for format: Int) -> String {
    switch format {
    case 0:
      return "jpg"
    case 1:
      return "png"
    case 2:
      return "webp"
    default:
      return "jpg"
    }
  }

  private static func imageData(from cgImage: CGImage, format: Int, quality: Int) throws -> Data {
    let rep = NSBitmapImageRep(cgImage: cgImage)
    switch format {
    case 1:
      if let data = rep.representation(using: .png, properties: [:]) {
        return data
      }
    case 2:
      // NSBitmapImageRep.FileType.webP is not available on all SDKs/toolchains,
      // so fall back to PNG for compatibility.
      if let data = rep.representation(using: .png, properties: [:]) {
        return data
      }
    default:
      if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: qualityFactor(quality)]) {
        return data
      }
    }
    throw NSError(
      domain: "flutter_video_thumbnail_plus",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Failed to encode thumbnail image"])
  }

  private static func qualityFactor(_ quality: Int) -> CGFloat {
    return CGFloat(max(0, min(quality, 100))) / 100.0
  }

  private static func generateThumbnail(
    url: URL,
    headers: [String: String]?,
    format: Int,
    maxHeight: Int,
    maxWidth: Int,
    timeMs: Int,
    quality: Int
  ) throws -> Data {
    var options: [String: Any] = [:]
    if let headers {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }

    let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.requestedTimeToleranceBefore = .zero
    imageGenerator.requestedTimeToleranceAfter = CMTime(value: 100, timescale: 1000)
    if maxWidth > 0 && maxHeight > 0 {
      imageGenerator.maximumSize = CGSize(width: maxWidth, height: maxHeight)
    }

    let targetTime = CMTime(value: Int64(timeMs), timescale: 1000)
    var actualTime = CMTime.zero
    do {
      let cgImage = try imageGenerator.copyCGImage(at: targetTime, actualTime: &actualTime)
      return try imageData(from: cgImage, format: format, quality: quality)
    } catch let avError {
      if url.isFileURL {
        do {
          if let fallback = try quickLookThumbnailData(
            fileURL: url,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            format: format,
            quality: quality)
          {
            return fallback
          }
        } catch {
          throw thumbnailOpenError(for: url, underlyingError: error)
        }
      }
      throw thumbnailOpenError(for: url, underlyingError: avError)
    }
  }

  private static func quickLookThumbnailData(
    fileURL: URL,
    maxWidth: Int,
    maxHeight: Int,
    format: Int,
    quality: Int
  ) throws -> Data? {
    if #available(macOS 10.15, *) {
      let width = max(1, maxWidth == 0 ? 512 : maxWidth)
      let height = max(1, maxHeight == 0 ? 512 : maxHeight)
      let request = QLThumbnailGenerator.Request(
        fileAt: fileURL,
        size: CGSize(width: width, height: height),
        scale: 1.0,
        representationTypes: .thumbnail)

      let semaphore = DispatchSemaphore(value: 0)
      var generatedData: Data?
      var generatedError: Error?

      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
        defer { semaphore.signal() }
        if let error {
          generatedError = error
          return
        }
        guard let cgImage = thumbnail?.cgImage else {
          return
        }
        do {
          generatedData = try imageData(from: cgImage, format: format, quality: quality)
        } catch {
          generatedError = error
        }
      }

      _ = semaphore.wait(timeout: .now() + 5)

      if let generatedData {
        return generatedData
      }
      if let generatedError {
        throw generatedError
      }
    }
    return nil
  }

  private static func thumbnailOpenError(for url: URL, underlyingError: Error) -> NSError {
    let ext = url.pathExtension.lowercased()
    var message = "Cannot open video for thumbnail generation on macOS."
    if ext == "webm" {
      message = "This .webm file codec is not supported by macOS thumbnail providers on this machine."
    }
    return NSError(
      domain: "flutter_video_thumbnail_plus",
      code: 2,
      userInfo: [
        NSLocalizedDescriptionKey: message,
        NSUnderlyingErrorKey: underlyingError
      ])
  }
}
