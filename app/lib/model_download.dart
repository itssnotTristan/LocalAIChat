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
  static const detailedVisionUrl =
      'https://huggingface.co/mradermacher/Qwen3.5-4B-Uncensored-GGUF/resolve/main/';
  static const detailedVisionName = 'Qwen3.5-4B-Uncensored.Q4_K_M.gguf';
  static const detailedProjectorName = 'Qwen3.5-4B-Uncensored.mmproj-Q8_0.gguf';
  static const detailedVisionSha256 =
      'f3a2e8f1837f52247a5b7b28f379923c98cc38fa8b339a943ba49b518be8b562';
  static const detailedProjectorSha256 =
      '04a3af332afa255093f04b1a95ae1065637c140b8b365f721f0be89b62ae2d16';
  static const roleplayUrl =
      'https://huggingface.co/mradermacher/Qwen3-4B-Nymphaea-RP-GGUF/resolve/main/';
  static const roleplayName = 'Qwen3-4B-Nymphaea-RP.Q4_K_M.gguf';
  static const roleplaySha256 =
      '7896e1c1e498554887ea6439c44939216f67146fa3c3298ee7a95c2cf206376d';

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

  Future<StarterModelFiles> downloadDetailedVision(
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
        detailedVisionName,
        detailedVisionSha256,
        onProgress,
        baseUrl: detailedVisionUrl,
      );
      final projector = await _downloadOne(
        folder,
        detailedProjectorName,
        detailedProjectorSha256,
        onProgress,
        baseUrl: detailedVisionUrl,
      );
      return StarterModelFiles(model, projector);
    } finally {
      _client?.close();
      _client = null;
    }
  }

  Future<String> downloadRoleplay(
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
        roleplayName,
        roleplaySha256,
        onProgress,
        baseUrl: roleplayUrl,
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
