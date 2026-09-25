import 'dart:typed_data';

import 'package:flutter_video_thumbnail_plus/enum.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_mobile_platform.dart'
    if (dart.library.html) 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_web.dart'
    as platform;
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_platform_interface.dart';

export 'enum.dart';

/// A utility class for generating thumbnails from video files and byte arrays.
///
/// This class provides a simple and efficient way to generate thumbnails from video files and byte arrays.
/// It supports various image formats, including PNG, JPG, and WebP, and allows for customization of the thumbnail's size, quality, and timestamp.
/// The generated thumbnails can be saved to a file or returned as a `Uint8List` for further processing.
///
/// Note that this class uses platform-specific implementations to generate thumbnails, which ensures optimal performance and compatibility.
class FlutterVideoThumbnailPlus {
  FlutterVideoThumbnailPlus._(); // coverage:ignore-line

  static FlutterVideoThumbnailPlusPlatform get _instance =>
      FlutterVideoThumbnailPlusPlatform.instance;

  /// Generates a thumbnail from a video file and saves it to a file.
  ///
  /// [video] is the path to the video file.
  /// [headers] is an optional map of headers to be sent with the request.
  /// [thumbnailPath] is the path where the thumbnail will be saved. If not provided, a default path will be used.
  /// [imageFormat] is the format of the thumbnail image. Defaults to `ImageFormat.png`.
  /// [maxHeight] is the maximum height of the thumbnail. Defaults to 0, which means the height will not be limited.
  /// [maxWidth] is the maximum width of the thumbnail. Defaults to 0, which means the width will not be limited.
  /// [timeMs] is the time in milliseconds at which to generate the thumbnail. Defaults to 0, which means the thumbnail will be generated at the beginning of the video.
  /// [quality] is the quality of the thumbnail. Defaults to 10.
  ///```dart
  /// final result = await FlutterVideoThumbnailPlus.thumbnailFile(
  ///  video:'provide-video-path',
  ///  thumbnailPath:'provide-if-exist-thumbnail-path,
  ///  imageFormat: 'provide-image-format- Like- ImageFormat.png',
  ///   maxHeight:'thumbnails Max Height'
  /// )
  ///```
  /// Returns a `Future` that resolves to the path of the generated thumbnail file, or `null` if the operation fails.
  static Future<String?> thumbnailFile({
    required String video,
    Map<String, String>? headers,
    String? thumbnailPath,
    ImageFormat imageFormat = ImageFormat.png,
    int maxHeight = 0,
    int maxWidth = 0,
    int timeMs = 0,
    int quality = 10,
  }) async =>
      await _instance.thumbnailFile(
        video: video,
        thumbnailPath: thumbnailPath,
        headers: headers,
        imageFormat: imageFormat,
        maxHeight: maxHeight,
        maxWidth: maxWidth,
        quality: quality,
        timeMs: timeMs,
      );

  /// Generates a thumbnail from a video file and returns the thumbnail data as a `Uint8List`.
  ///
  /// [video] is the path to the video file.
  /// [headers] is an optional map of headers to be sent with the request.
  /// [imageFormat] is the format of the thumbnail image. Defaults to `ImageFormat.png`.
  /// [maxHeight] is the maximum height of the thumbnail. Defaults to 0, which means the height will not be limited.
  /// [maxWidth] is the maximum width of the thumbnail. Defaults to 0, which means the width will not be limited.
  /// [timeMs] is the time in milliseconds at which to generate the thumbnail. Defaults to 0, which means the thumbnail will be generated at the beginning of the video.
  /// [quality] is the quality of the thumbnail. Defaults to 10.
  ///
  /// Returns a `Future` that resolves to the thumbnail data as a `Uint8List`, or `null` if the operation fails
  static Future<Uint8List?> thumbnailData({
    required String video,
    Map<String, String>? headers,
    ImageFormat imageFormat = ImageFormat.png,
    int maxHeight = 0,
    int maxWidth = 0,
    int timeMs = 0,
    int quality = 10,
  }) async =>
      await _instance.thumbnailData(
        video: video,
        headers: headers,
        imageFormat: imageFormat,
        maxHeight: maxHeight,
        maxWidth: maxWidth,
        quality: quality,
        timeMs: timeMs,
      );

  /// Generates a thumbnail from a video byte array and returns the thumbnail data as a `Uint8List`.
  ///
  /// [videoBytes] is the video byte array.
  /// [quality] is the quality of the thumbnail. Defaults to 100.
  ///
  /// Returns a `Future` that resolves to the thumbnail data as a `Uint8List`, or `null` if the operation fails.
  ///
  /// Note: This method is only available on the web platform.
  static Future<Uint8List?> thumbnailDataWeb({
    required Uint8List videoBytes,
    num quality = 100,
  }) async =>
      await platform.FlutterVideoThumbnailPlusWeb().thumbnailDataWeb(
        videoBytes: videoBytes,
        quality: quality,
      );
}
