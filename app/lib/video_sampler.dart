import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';

class VideoSample {
  const VideoSample(this.path, this.timeMs);
  final String path;
  final int timeMs;
}

class _Candidate {
  const _Candidate(this.timeMs, this.signature);
  final int timeMs;
  final Uint8List signature;
}

/// Scans short clips at up to eight positions per second and keeps both
/// time-spaced coverage and visually changed moments. A user can also add an
/// exact timestamp through [extractAt].
class VideoSampler {
  static Future<List<VideoSample>> sample({
    required String video,
    required int durationMs,
    required int frameLimit,
    required Directory outputDir,
    void Function(int done, int total)? onProgress,
  }) async {
    if (durationMs <= 0) throw ArgumentError.value(durationMs, 'durationMs');
    await outputDir.create(recursive: true);
    final scanDir = await Directory(
      '${outputDir.path}${Platform.pathSeparator}scan_${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    final count = math.min(240, math.max(16, (durationMs / 125).ceil()));
    final candidates = <_Candidate>[];
    try {
      for (var i = 0; i < count; i++) {
        final timeMs = ((i + 0.5) * durationMs / count).round();
        final path = '${scanDir.path}${Platform.pathSeparator}$i.jpg';
        final output = await FlutterVideoThumbnailPlus.thumbnailFile(
          video: video,
          thumbnailPath: path,
          imageFormat: ImageFormat.jpeg,
          maxWidth: 128,
          maxHeight: 128,
          quality: 55,
          timeMs: timeMs,
        );
        if (output != null && await File(output).exists()) {
          candidates.add(_Candidate(timeMs, await _signature(output)));
        }
        if (i % 8 == 0 || i + 1 == count) onProgress?.call(i + 1, count);
      }
      if (candidates.isEmpty) {
        throw StateError('Could not decode any frames from this video.');
      }
      final selected = _select(
        candidates,
        math.min(frameLimit, candidates.length),
      );
      final results = <VideoSample>[];
      for (final index in selected) {
        results.add(
          await extractAt(
            video: video,
            timeMs: candidates[index].timeMs,
            outputDir: outputDir,
          ),
        );
      }
      return results;
    } finally {
      if (await scanDir.exists()) await scanDir.delete(recursive: true);
    }
  }

  static Future<VideoSample> extractAt({
    required String video,
    required int timeMs,
    required Directory outputDir,
  }) async {
    await outputDir.create(recursive: true);
    final path =
        '${outputDir.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}_$timeMs.jpg';
    final output = await FlutterVideoThumbnailPlus.thumbnailFile(
      video: video,
      thumbnailPath: path,
      imageFormat: ImageFormat.jpeg,
      maxWidth: 768,
      maxHeight: 768,
      quality: 82,
      timeMs: timeMs,
    );
    if (output == null || !await File(output).exists()) {
      throw StateError('Could not extract the video frame at $timeMs ms.');
    }
    return VideoSample(output, timeMs);
  }

  static List<int> _select(List<_Candidate> frames, int limit) {
    final chosen = <int>{};
    final anchors = math.max(2, limit ~/ 3);
    for (var i = 0; i < anchors; i++) {
      chosen.add(
        ((i + 0.5) * frames.length / anchors).floor().clamp(
          0,
          frames.length - 1,
        ),
      );
    }
    final scores = List<double>.filled(frames.length, 0);
    for (var i = 0; i < frames.length; i++) {
      final previous = i > 0
          ? _difference(frames[i].signature, frames[i - 1].signature)
          : 0.0;
      final next = i + 1 < frames.length
          ? _difference(frames[i].signature, frames[i + 1].signature)
          : 0.0;
      final distant = i >= 8
          ? _difference(frames[i].signature, frames[i - 8].signature)
          : 0.0;
      scores[i] = math.max(math.max(previous, next), distant);
    }
    final minimumGap = math.max(1, frames.length ~/ (limit * 3));
    bool addIfDistinct(int index) {
      if (chosen.any((other) => (other - index).abs() < minimumGap))
        return false;
      chosen.add(index);
      return true;
    }

    final buckets = math.min(4, limit - chosen.length);
    for (var bucket = 0; bucket < buckets; bucket++) {
      final start = bucket * frames.length ~/ buckets;
      final end = (bucket + 1) * frames.length ~/ buckets;
      final ranked = [for (var i = start; i < end; i++) i]
        ..sort((a, b) => scores[b].compareTo(scores[a]));
      for (final index in ranked) {
        if (addIfDistinct(index)) break;
      }
    }
    final ranked = [for (var i = 0; i < frames.length; i++) i]
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    for (final index in ranked) {
      if (chosen.length >= limit) break;
      addIfDistinct(index);
    }
    for (final index in ranked) {
      if (chosen.length >= limit) break;
      chosen.add(index);
    }
    return chosen.toList()..sort();
  }

  static double _difference(Uint8List a, Uint8List b) {
    var total = 0;
    for (var i = 0; i < a.length; i++) {
      total += (a[i] - b[i]).abs();
    }
    return total / a.length;
  }

  static Future<Uint8List> _signature(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
      targetWidth: 32,
    );
    try {
      final frame = await codec.getNextFrame();
      final picture = frame.image;
      try {
        final data = await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null)
          throw StateError('Could not read decoded video frame.');
        final bytes = data.buffer.asUint8List();
        final signature = Uint8List(8 * 8 * 3);
        var next = 0;
        for (var row = 0; row < 8; row++) {
          for (var column = 0; column < 8; column++) {
            final x = ((column + 0.5) * picture.width / 8).floor();
            final y = ((row + 0.5) * picture.height / 8).floor();
            final offset = (y * picture.width + x) * 4;
            signature[next++] = bytes[offset];
            signature[next++] = bytes[offset + 1];
            signature[next++] = bytes[offset + 2];
          }
        }
        return signature;
      } finally {
        picture.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
