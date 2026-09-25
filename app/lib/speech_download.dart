import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import 'speech_service.dart';

/// Downloads only after explicit user action, then extracts speech weights
/// entirely on the current device.
class SpeechDownloader {
  HttpClient? _client;
  bool _cancelled = false;

  static const _asrUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-moonshine-tiny-en-int8.tar.bz2';
  static const _ttsUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-ljs.tar.bz2';
  static const _asrSha =
      'd5fe6ec4334fef36255b2a4010412cad4c007e33103fec62fb5d17cad88086f2';
  static const _ttsSha =
      '78f7df445fcd42d1dd6df2c78c66c2c2fee8b7abecc6ae255a5950097a6558bc';

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> download(
    String root,
    void Function(String, int, int?) progress,
  ) async {
    if (await SpeechService.hasModels(root)) return;
    _cancelled = false;
    _client = HttpClient();
    final directory = Directory(root);
    await directory.create(recursive: true);
    try {
      final asr = await _file(
        directory,
        'moonshine-tiny-en-int8.tar.bz2',
        _asrUrl,
        _asrSha,
        progress,
      );
      final tts = await _file(
        directory,
        'vits-ljs.tar.bz2',
        _ttsUrl,
        _ttsSha,
        progress,
      );
      if (_cancelled)
        throw const HttpException('Speech model download cancelled.');
      progress('Extracting speech models', 0, null);
      await Isolate.run(() async {
        await extractFileToDisk(asr, root);
        await extractFileToDisk(tts, root);
      });
      if (!await SpeechService.hasModels(root)) {
        throw StateError('Extracted speech files are incomplete.');
      }
      // Validated extracted files are retained; archives can be reacquired.
      await File(asr).delete();
      await File(tts).delete();
    } finally {
      _client?.close();
      _client = null;
    }
  }

  Future<String> _file(
    Directory directory,
    String name,
    String url,
    String expectedSha,
    void Function(String, int, int?) progress,
  ) async {
    final file = File(directory.path + Platform.pathSeparator + name);
    if (await file.exists()) {
      if (await _digest(file) == expectedSha) return file.path;
      throw StateError('Existing $name has an unexpected checksum.');
    }
    final partial = File(file.path + '.part');
    var offset = await partial.exists() ? await partial.length() : 0;
    final request = await _client!.getUrl(Uri.parse(url));
    if (offset > 0)
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
    }
    if (response.statusCode == HttpStatus.ok) offset = 0;
    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    final total = response.contentLength < 0
        ? null
        : offset + response.contentLength;
    var received = offset;
    try {
      await for (final chunk in response) {
        if (_cancelled) throw const HttpException('Download cancelled.');
        sink.add(chunk);
        received += chunk.length;
        progress(name, received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (_cancelled) throw const HttpException('Download cancelled.');
    if (total != null && total != received) {
      throw StateError('Download ended early. Tap again to resume.');
    }
    if (await _digest(partial) != expectedSha) {
      await partial.delete();
      throw StateError('$name failed SHA-256 verification.');
    }
    await partial.rename(file.path);
    return file.path;
  }

  Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
