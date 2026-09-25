import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class GgufInfo {
  const GgufInfo({
    required this.architecture,
    required this.name,
    required this.quantization,
    required this.contextLength,
    required this.sizeBytes,
  });
  final String architecture;
  final String name;
  final String quantization;
  final int? contextLength;
  final int sizeBytes;

  /// Reads only GGUF metadata. Tensor weights are never loaded into Dart.
  static Future<GgufInfo> read(String path) async {
    final file = File(path);
    final size = await file.length();
    if (size < 32)
      throw const FormatException('File is too small to be a GGUF model.');
    final handle = file.openSync();
    try {
      final reader = _GgufReader(handle, size);
      if (ascii.decode(reader.bytes(4)) != 'GGUF') {
        throw const FormatException('The selected file is not GGUF.');
      }
      final version = reader.u32();
      if (version < 2 || version > 3) {
        throw FormatException(
          'GGUF version $version is not supported by this importer.',
        );
      }
      reader.u64(); // tensor count
      final count = reader.u64();
      if (count > 100000)
        throw const FormatException('GGUF metadata count is invalid.');
      final values = <String, Object?>{};
      for (var index = 0; index < count; index++) {
        final key = reader.string(maxLength: 1024);
        final type = reader.u32();
        final keep =
            key == 'general.architecture' ||
            key == 'general.name' ||
            key == 'general.file_type' ||
            key.endsWith('.context_length');
        final value = reader.value(type, keep: keep);
        if (keep) values[key] = value;
      }
      final architecture =
          values['general.architecture']?.toString() ?? 'unknown';
      final name =
          values['general.name']?.toString() ??
          path.split(RegExp(r'[/\\]')).last;
      final fileType = values['general.file_type'];
      final context =
          values['$architecture.context_length'] ??
          values.entries
              .where((entry) => entry.key.endsWith('.context_length'))
              .map((entry) => entry.value)
              .firstOrNull;
      return GgufInfo(
        architecture: architecture,
        name: name,
        quantization: fileType == null ? 'unknown' : 'GGUF file type $fileType',
        contextLength: context is int ? context : null,
        sizeBytes: size,
      );
    } finally {
      handle.closeSync();
    }
  }
}

class _GgufReader {
  _GgufReader(this.handle, this.fileSize);
  final RandomAccessFile handle;
  final int fileSize;

  Uint8List bytes(int length) {
    if (length < 0 || handle.positionSync() + length > fileSize) {
      throw const FormatException('GGUF metadata is truncated or invalid.');
    }
    final result = handle.readSync(length);
    if (result.length != length)
      throw const FormatException('GGUF read ended early.');
    return result;
  }

  void skip(int length) {
    if (length < 0 || handle.positionSync() + length > fileSize) {
      throw const FormatException('GGUF metadata length is invalid.');
    }
    handle.setPositionSync(handle.positionSync() + length);
  }

  int u32() => ByteData.sublistView(bytes(4)).getUint32(0, Endian.little);
  int u64() => ByteData.sublistView(bytes(8)).getUint64(0, Endian.little);

  String string({int maxLength = 1000000}) {
    final length = u64();
    if (length > maxLength)
      throw const FormatException('GGUF metadata string is too long.');
    return utf8.decode(bytes(length), allowMalformed: true);
  }

  Object? value(int type, {required bool keep}) {
    switch (type) {
      case 0: // uint8
        if (!keep) {
          skip(1);
          return null;
        }
        return bytes(1)[0];
      case 1: // int8
        if (!keep) {
          skip(1);
          return null;
        }
        return ByteData.sublistView(bytes(1)).getInt8(0);
      case 2: // uint16
        if (!keep) {
          skip(2);
          return null;
        }
        return ByteData.sublistView(bytes(2)).getUint16(0, Endian.little);
      case 3: // int16
        if (!keep) {
          skip(2);
          return null;
        }
        return ByteData.sublistView(bytes(2)).getInt16(0, Endian.little);
      case 4: // uint32
        if (!keep) {
          skip(4);
          return null;
        }
        return u32();
      case 5: // int32
        if (!keep) {
          skip(4);
          return null;
        }
        return ByteData.sublistView(bytes(4)).getInt32(0, Endian.little);
      case 6: // float32
        if (!keep) {
          skip(4);
          return null;
        }
        return ByteData.sublistView(bytes(4)).getFloat32(0, Endian.little);
      case 7: // bool
        if (!keep) {
          skip(1);
          return null;
        }
        return bytes(1)[0] != 0;
      case 8: // string
        final length = u64();
        if (length > 100000000)
          throw const FormatException('GGUF string length is invalid.');
        if (!keep) {
          skip(length);
          return null;
        }
        return utf8.decode(bytes(length), allowMalformed: true);
      case 9: // array
        final elementType = u32();
        final count = u64();
        if (count > 100000000)
          throw const FormatException('GGUF array length is invalid.');
        for (var i = 0; i < count; i++) {
          value(elementType, keep: false);
        }
        return null;
      case 10: // uint64
        if (!keep) {
          skip(8);
          return null;
        }
        return u64();
      case 11: // int64
        if (!keep) {
          skip(8);
          return null;
        }
        return ByteData.sublistView(bytes(8)).getInt64(0, Endian.little);
      case 12: // float64
        if (!keep) {
          skip(8);
          return null;
        }
        return ByteData.sublistView(bytes(8)).getFloat64(0, Endian.little);
      default:
        throw FormatException('Unsupported GGUF metadata type $type.');
    }
  }
}
