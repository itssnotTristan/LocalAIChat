import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// A web implementation of the FlutterVideoThumbnailPlusPlatform of the FlutterVideoThumbnailPlus plugin.
class FlutterVideoThumbnailPlusWeb extends FlutterVideoThumbnailPlusPlatform {
  /// Constructs a FlutterVideoThumbnailPlusWeb
  FlutterVideoThumbnailPlusWeb();

  static void registerWith(Registrar registrar) {
    FlutterVideoThumbnailPlusPlatform.instance = FlutterVideoThumbnailPlusWeb();
  }

  @override
  Future<Uint8List?> thumbnailDataWeb({
    required Uint8List videoBytes,
    num quality = 100,
  }) async {
    assert(videoBytes.isNotEmpty,
        'Error: Video byte array is empty. Please ensure the video file is loaded correctly.');
    var thumbnailBytes = Uint8List(0);
    try {
      final blob = web.Blob(
        [videoBytes.buffer.toJS].toJS,
        web.BlobPropertyBag(type: 'video/mp4'),
      );
      final url = web.URL.createObjectURL(blob);
      final videoElement = web.HTMLVideoElement()
        ..src = url
        ..autoplay = false
        ..controls = false
        ..muted = true
        ..style.display = 'none';

      videoElement.play();
      return await Future.delayed(
        const Duration(seconds: 1),
        () async {
          videoElement.pause();
          final canvas = web.HTMLCanvasElement()
            ..width = videoElement.videoWidth
            ..height = videoElement.videoHeight;
          final context =
              canvas.getContext('2d')! as web.CanvasRenderingContext2D;
          context.drawImage(videoElement, 0, 0);
          final thumbnailUrl = canvas.toDataUrl('image/jpeg', quality);
          web.URL.revokeObjectURL(url);

          // Convert data URL to bytes
          final byteString = thumbnailUrl.split(',').last;
          final bytes = base64.decode(byteString);
          thumbnailBytes = Uint8List.fromList(bytes);
          return thumbnailBytes;
        },
      );
    } catch (e) {
      throw Exception('Please Provide Valid Video Bytes as Uint8List: $e');
    }
  }
}
