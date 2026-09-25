import 'dart:io';

import 'package:crypto/crypto.dart';

class StarterModelFiles {
  const StarterModelFiles(this.model, this.projector);
  final String model;
  final String projector;
}

/// Network access is created only when the user taps a download button.
class ModelDownloader {
  HttpClient? _client;
  bool _cancelled = false;

  static const base =
      'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/';
  static const modelName = 'SmolVLM2-500M-Video-Instruct-Q8_0.gguf';
  static const projectorName = 'mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf';
  static const modelSha256 =
      '6f67b8036b2469fcd71728702720c6b51aebd759b78137a8120733b4d66438bc';
  static const projectorSha256 =
      '921dc7e259f308e5b027111fa185efcbf33db13f6e35749ddf7f5cdb60ef520b';
  static const adultTextUrl =
      'https://huggingface.co/mradermacher/Qwen2.5-1.5B-Instruct-abliterated-GGUF/resolve/main/';
  static const adultTextName = 'Qwen2.5-1.5B-Instruct-abliterated.Q4_K_M.gguf';
  static const adultTextSha256 =
      '59aa9f44bde5349dbe292d7024d197db605f422b8baf65f3246a59abbde4e8e9';

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<StarterModelFiles> downloadStarter(
    String directory,
    void Function(String name, int received, int? total) onProgress,
  ) async {
    _cancelled = false;
    _client = HttpClient();
    final folder = Directory(directory);
    await folder.create(recursive: true);
    try {
      final model = await _downloadOne(
        folder,
        modelName,
        modelSha256,
        onProgress,
      );
      final projector = await _downloadOne(
        folder,
        projectorName,
        projectorSha256,
        onProgress,
      );
      return StarterModelFiles(model, projector);
    } finally {
      _client?.close();
      _client = null;
    }
  }

  Future<String> downloadAdultText(
    String directory,
    void Function(String name, int received, int? total) onProgress,
  ) async {
    _cancelled = false;
    _client = HttpClient();
    final folder = Directory(directory);
    await folder.create(recursive: true);
    try {
      return await _downloadOne(
        folder,
        adultTextName,
        adultTextSha256,
        onProgress,
        baseUrl: adultTextUrl,
      );
    } finally {
      _client?.close();
      _client = null;
    }
  }

  Future<String> _downloadOne(
    Directory folder,
    String name,
    String expectedSha,
    void Function(String, int, int?) onProgress, {
    String baseUrl = base,
  }) async {
    final file = File(folder.path + Platform.pathSeparator + name);
    if (await file.exists()) {
      if (await _digest(file) == expectedSha) {
        onProgress(name, await file.length(), await file.length());
        return file.path;
      }
      throw StateError(
        'Existing $name has the wrong checksum. Move it aside before retrying.',
      );
    }
    final partial = File(file.path + '.part');
    var offset = await partial.exists() ? await partial.length() : 0;
    final request = await _client!.getUrl(Uri.parse(baseUrl + name));
    if (offset > 0)
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException(
        'Download returned HTTP ${response.statusCode}',
        uri: request.uri,
      );
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
        onProgress(name, received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (_cancelled) throw const HttpException('Download cancelled.');
    if (total != null && received != total) {
      throw StateError('Download ended early. Tap again to resume.');
    }
    final actualSha = await _digest(partial);
    if (actualSha != expectedSha) {
      await partial.delete();
      throw StateError('$name failed SHA-256 verification.');
    }
    await partial.rename(file.path);
    return file.path;
  }

  Future<String> _digest(File file) async {
    final result = await sha256.bind(file.openRead()).first;
    return result.toString();
  }
}
