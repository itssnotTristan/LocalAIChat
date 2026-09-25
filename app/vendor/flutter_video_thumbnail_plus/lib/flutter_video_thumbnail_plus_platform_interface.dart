import 'dart:typed_data';
import 'package:flutter_video_thumbnail_plus/enum.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class FlutterVideoThumbnailPlusPlatform extends PlatformInterface {
  /// Constructs a FlutterVideoThumbnailPlusPlatform.
  FlutterVideoThumbnailPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterVideoThumbnailPlusPlatform _instance =
      MethodChannelFlutterVideoThumbnailPlus();

  /// The default instance of [FlutterVideoThumbnailPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterVideoThumbnailPlus].
  static FlutterVideoThumbnailPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterVideoThumbnailPlusPlatform] when
  /// they register themselves.
  static set instance(FlutterVideoThumbnailPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> thumbnailFile(
      {required String video,
      Map<String, String>? headers,
      String? thumbnailPath,
      ImageFormat imageFormat = ImageFormat.png,
      int maxHeight = 0,
      int maxWidth = 0,
      int timeMs = 0,
      int quality = 10}) async {
    throw UnimplementedError('thumbnailFile() has not been implemented.');
  }

  Future<Uint8List?> thumbnailData({
    required String video,
    Map<String, String>? headers,
    ImageFormat imageFormat = ImageFormat.png,
    int maxHeight = 0,
    int maxWidth = 0,
    int timeMs = 0,
    int quality = 10,
  }) async {
    throw UnimplementedError('thumbnailData() has not been implemented.');
  }

  Future<Uint8List?> thumbnailDataWeb({
    required Uint8List videoBytes,
    num quality = 100,
  }) async {
    throw UnimplementedError('thumbnailDataWeb() has not been implemented.');
  }
}
