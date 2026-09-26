import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import 'image_studio_engine.dart';

class ImageStudioInstaller {
  ImageStudioInstaller(this.root);

  final String root;
  HttpClient? _client;
  bool _cancelled = false;

  static const iosModelUrl =
      'https://huggingface.co/darkmaniac7/TokForge-RealisticVision-5.1-CoreML-6bit/resolve/c4c933a49ac1077166da765d14aae885e08317b3/RealisticVision-5.1_palettized_split_einsum_v2_compiled.zip';
  static const iosModelSha =
      'f39611acf39178af4f13e5c29205f80a48dc92d8a78c63fcbc0bad203d6fc87e';

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> install(void Function(String) status) async {
    _cancelled = false;
    _client = HttpClient();
    try {
      if (Platform.isIOS) {
        if (await findCoreMLResourcesAt('$root/coreml/realistic-vision-5.1') ==
            null) {
          final zip = await _download(
            iosModelUrl,
            '$root/coreml/realistic-vision-5.1.zip',
            expectedBytes: 916522756,
            sha256Hex: iosModelSha,
            status: status,
          );
          status('Installing the local iPhone image model…');
          await Isolate.run(
            () => extractFileToDisk(zip, '$root/coreml/realistic-vision-5.1'),
          );
          if (await findCoreMLResourcesAt(
                '$root/coreml/realistic-vision-5.1',
              ) ==
              null) {
            throw StateError(
              'The image model is missing the files needed for photo editing.',
            );
          }
        }
        final resources = await findCoreMLResourcesAt(
          '$root/coreml/realistic-vision-5.1',
        );
        if (resources == null) {
          throw StateError(
            'The image model is incomplete. Tap Install to retry.',
          );
        }
        // The archive is pinned by size and SHA-256, and every required Core ML
        // resource is checked above. Loading the full diffusion pipeline here
        // can take minutes or exhaust memory before the user has even edited.
        status('Image model files ready. The first edit will load the model.');
        await _removeRetiredIphoneModel();
      } else {
        throw UnsupportedError('Image Studio is available on iPhone.');
      }
    } finally {
      _client?.close();
      _client = null;
    }
  }

  /// Once the new model is complete, reclaim only the previous app-managed
  /// SD 1.5 download and its top-level extracted resources.
  Future<void> _removeRetiredIphoneModel() async {
    for (final name in [
      'coreml-sd15-split.zip',
      'coreml-sd15-split.zip.part',
      'realistic-vision-5.1.zip',
    ]) {
      final file = File('$root/coreml/$name');
      if (await file.exists()) await file.delete();
    }
    for (final name in [
      'Resources',
      'coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled',
    ]) {
      final directory = Directory('$root/coreml/$name');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<String> _download(
    String url,
    String output, {
    required int expectedBytes,
    String? sha256Hex,
    required void Function(String) status,
  }) async {
    final file = File(output);
    await file.parent.create(recursive: true);
    if (await file.exists() && await file.length() == expectedBytes) {
      if (sha256Hex == null ||
          (await sha256.bind(file.openRead()).first).toString() == sha256Hex) {
        return output;
      }
      await file.delete();
    }
    final partial = File('$output.part');
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > expectedBytes) {
      await partial.delete();
      offset = 0;
    }
    if (offset == expectedBytes) {
      if (sha256Hex != null &&
          (await sha256.bind(partial.openRead()).first).toString() !=
              sha256Hex) {
        await partial.delete();
      } else {
        await partial.rename(output);
        return output;
      }
      offset = 0;
    }
    final request = await _client!.getUrl(Uri.parse(url));
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException(
        'Image model download returned HTTP ${response.statusCode}.',
      );
    }
    if (response.statusCode == HttpStatus.ok) offset = 0;
    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var received = offset;
    var lastUpdate = 0;
    try {
      await for (final chunk in response) {
        if (_cancelled) {
          throw StateError('Download paused. Tap Install to resume.');
        }
        sink.add(chunk);
        received += chunk.length;
        if (received - lastUpdate >= 8 * 1048576) {
          lastUpdate = received;
          status(
            'Downloading image model · ${(received / 1048576).toStringAsFixed(0)} / ${(expectedBytes / 1048576).toStringAsFixed(0)} MiB',
          );
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received != expectedBytes) {
      throw StateError('Download stopped early. Tap Install to resume.');
    }
    if (sha256Hex != null) {
      status('Checking image model download…');
      final actual = (await sha256.bind(partial.openRead()).first).toString();
      if (actual != sha256Hex) {
        throw StateError('Image model download failed its checksum.');
      }
    }
    await partial.rename(output);
    return output;
  }
}
