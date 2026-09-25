import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_video_thumbnail_plus/enum.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_platform_interface.dart';

/// An implementation of [FlutterVideoThumbnailPlusPlatform] that uses method channels.
class MethodChannelFlutterVideoThumbnailPlus
    extends FlutterVideoThumbnailPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_video_thumbnail_plus');

  @override
  Future<String?> thumbnailFile(
      {required String video,
      Map<String, String>? headers,
      String? thumbnailPath,
      ImageFormat imageFormat = ImageFormat.png,
      int maxHeight = 0,
      int maxWidth = 0,
      int timeMs = 0,
      int quality = 10}) async {
    if (video.isEmpty) return null;
    final reqMap = <String, dynamic>{
      'video': video,
      'headers': headers,
      'path': thumbnailPath,
      'format': imageFormat.index,
      'maxh': maxHeight,
      'maxw': maxWidth,
      'timeMs': timeMs,
      'quality': quality
    };
    return await methodChannel.invokeMethod('file', reqMap);
  }

  @override
  Future<Uint8List?> thumbnailData({
    required String video,
    Map<String, String>? headers,
    ImageFormat imageFormat = ImageFormat.png,
    int maxHeight = 0,
    int maxWidth = 0,
    int timeMs = 0,
    int quality = 10,
  }) async {
    assert(video.isNotEmpty);
    final reqMap = <String, dynamic>{
      'video': video,
      'headers': headers,
      'format': imageFormat.index,
      'maxh': maxHeight,
      'maxw': maxWidth,
      'timeMs': timeMs,
      'quality': quality,
    };
    return await methodChannel.invokeMethod('data', reqMap);
  }
}
