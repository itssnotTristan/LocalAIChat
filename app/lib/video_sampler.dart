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
  const _Candidate(this.timeMs, this.signature, {this.path});
  final int timeMs;
  final Uint8List signature;
  final String? path;
}

/// Scans short clips at up to eight positions per second and keeps both
/// time-spaced coverage and visually changed moments. A user can also add an
/// exact timestamp through [extractAt].
class VideoSampler {
  /// Windows Media Foundation may not play iPhone HEVC/Dolby Vision files.
  /// Keep the original for analysis and create a local H.264 viewing copy.
  static Future<String> prepareWindowsPlayback({
    required String source,
    required String destination,
  }) async {
    if (!Platform.isWindows) return source;
    final ffmpeg = await _ffmpegExecutable();
    if (ffmpeg == null) {
      throw StateError('FFmpeg is required to play this video on Windows.');
    }
    final result = await Process.run(ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-threads',
      '4',
      '-i',
      source,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-vf',
      'scale=1280:1280:force_original_aspect_ratio=decrease:force_divisible_by=2',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '21',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '160k',
      '-movflags',
      '+faststart',
      destination,
    ]);
    if (result.exitCode != 0 || !await File(destination).exists()) {
      throw StateError('Could not prepare video playback: ${result.stderr}');
    }
    return destination;
  }

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
      final ffmpeg = await _ffmpegExecutable();
      if (ffmpeg != null) {
        final template =
            '${scanDir.path}${Platform.pathSeparator}frame_%04d.jpg';
        final result = await Process.run(ffmpeg, [
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-threads',
          '4',
          '-i',
          video,
          '-vf',
          'fps=8,scale=512:512:force_original_aspect_ratio=decrease',
          '-frames:v',
          count.toString(),
          '-q:v',
          '3',
          template,
        ]);
        if (result.exitCode != 0) {
          throw StateError('Could not decode video: ${result.stderr}');
        }
        final files =
            await scanDir
                  .list()
                  .where((entry) => entry is File)
                  .cast<File>()
                  .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (var i = 0; i < files.length; i++) {
          candidates.add(
            _Candidate(
              math.min(i * 125, durationMs - 1),
              await _signature(files[i].path),
              path: files[i].path,
            ),
          );
          if (i % 8 == 0 || i + 1 == files.length)
            onProgress?.call(i + 1, files.length);
        }
      } else {
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
        final candidate = candidates[index];
        if (candidate.path != null) {
          final path =
              '${outputDir.path}${Platform.pathSeparator}'
              '${DateTime.now().microsecondsSinceEpoch}_${candidate.timeMs}.jpg';
          await File(candidate.path!).copy(path);
          results.add(VideoSample(path, candidate.timeMs));
        } else {
          results.add(
            await extractAt(
              video: video,
              timeMs: candidate.timeMs,
              outputDir: outputDir,
              maxDimension: 512,
            ),
          );
        }
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
    int maxDimension = 768,
  }) async {
    await outputDir.create(recursive: true);
    final path =
        '${outputDir.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}_$timeMs.jpg';
    final ffmpeg = await _ffmpegExecutable();
    if (ffmpeg != null) {
      final result = await Process.run(ffmpeg, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-threads',
        '4',
        '-ss',
        (timeMs / 1000).toStringAsFixed(3),
        '-i',
        video,
        '-frames:v',
        '1',
        '-vf',
        'scale=$maxDimension:$maxDimension:force_original_aspect_ratio=decrease',
        '-q:v',
        '3',
        path,
      ]);
      if (result.exitCode != 0 || !await File(path).exists()) {
        throw StateError(
          'Could not extract the video frame at $timeMs ms: ${result.stderr}',
        );
      }
      return VideoSample(path, timeMs);
    }
    final output = await FlutterVideoThumbnailPlus.thumbnailFile(
      video: video,
      thumbnailPath: path,
      imageFormat: ImageFormat.jpeg,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      quality: 82,
      timeMs: timeMs,
    );
    if (output == null || !await File(output).exists()) {
      throw StateError('Could not extract the video frame at $timeMs ms.');
    }
    return VideoSample(output, timeMs);
  }

  static Future<String?> _ffmpegExecutable() async {
    if (!Platform.isWindows) return null;
    final bundled =
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}ffmpeg.exe';
    for (final path in [
      bundled,
      Platform.environment['LOCAL_AI_FFMPEG'],
      'D:\\LocalAIChat\\tools\\ffmpeg.exe',
    ]) {
      if (path != null && await File(path).exists()) return path;
    }
    return null;
  }

  static List<int> _select(List<_Candidate> frames, int limit) {
    final chosen = <int>{};
    chosen.add(0);
    if (limit > 1) chosen.add(frames.length - 1);
    final anchors = math.max(1, limit ~/ 4);
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
    final minimumGap = math.max(1, frames.length ~/ (limit * 2));
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
