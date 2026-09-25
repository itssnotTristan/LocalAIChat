import 'dart:io';
import 'dart:typed_data';

import 'package:media_metadata/media_metadata.dart';

/// Reads a video's duration locally. Windows Shell metadata can omit it for a
/// perfectly valid MP4, so ISO base media files have a direct parser fallback.
class VideoDuration {
  static Future<Duration> read(String path) async {
    try {
      final duration = (await MediaMetadata.read(path))?.duration;
      if (duration != null && duration > Duration.zero) return duration;
    } catch (_) {
      // Try the container itself before reporting an unsupported file.
    }
    final duration = await readMp4(path);
    if (duration != null && duration > Duration.zero) return duration;
    throw StateError('Could not read this video duration. MP4 and MOV are supported.');
  }

  /// Parses the movie header of MP4/MOV files without sending media anywhere.
  static Future<Duration?> readMp4(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final reader = await file.open();
    try {
      final length = await reader.length();
      final movie = await _findBox(reader, 0, length, 'moov');
      if (movie == null) return null;
      final header = await _findBox(reader, movie.start, movie.end, 'mvhd');
      if (header == null) return null;
      await reader.setPosition(header.start);
      final version = (await reader.read(1)).single;
      if (version != 0 && version != 1) return null;
      final offset = version == 1 ? 20 : 12;
      await reader.setPosition(header.start + offset);
      final needed = version == 1 ? 12 : 8;
      if (header.start + offset + needed > header.end) return null;
      final fields = ByteData.sublistView(Uint8List.fromList(await reader.read(needed)));
      final timescale = fields.getUint32(0, Endian.big);
      final units = version == 1
          ? fields.getUint64(4, Endian.big)
          : fields.getUint32(4, Endian.big);
      if (timescale == 0 || units == 0) return null;
      return Duration(milliseconds: (units * 1000 ~/ timescale));
    } on FormatException {
      return null;
    } finally {
      await reader.close();
    }
  }

  static Future<_Box?> _findBox(
    RandomAccessFile reader,
    int start,
    int end,
    String kind,
  ) async {
    var cursor = start;
    while (cursor + 8 <= end) {
      await reader.setPosition(cursor);
      final bytes = await reader.read(16);
      if (bytes.length < 8) return null;
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      final size32 = data.getUint32(0, Endian.big);
      final name = String.fromCharCodes(bytes.sublist(4, 8));
      final headerSize = size32 == 1 ? 16 : 8;
      if (bytes.length < headerSize) return null;
      final size = size32 == 1
          ? data.getUint64(8, Endian.big)
          : size32 == 0
          ? end - cursor
          : size32;
      if (size < headerSize || cursor + size > end) return null;
      final box = _Box(cursor + headerSize, cursor + size);
      if (name == kind) return box;
      cursor += size;
    }
    return null;
  }
}

class _Box {
  const _Box(this.start, this.end);
  final int start;
  final int end;
}
