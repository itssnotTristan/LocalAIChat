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

  static const windowsModelUrl =
      'https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors';
  static const windowsModelSha =
      '6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa';
  static const windowsRuntimeUrl =
      'https://github.com/leejet/stable-diffusion.cpp/releases/download/master-920-2f88688/sd-master-2f88688-bin-win-cuda12-x64.zip';
  static const windowsRuntimeSha =
      '479133a03d5c861ce77e70354dbbe75dd6e8d9955d1d1c7b6b1456b4571e3039';
  static const cudaBlasUrl =
      'https://developer.download.nvidia.com/compute/cuda/redist/libcublas/windows-x86_64/libcublas-windows-x86_64-12.8.4.1-archive.zip';
  static const cudaBlasSha =
      '57a470112cec7e112c95253dde8b3c7184d795dbd92b0bde77a4cb7f8c94c8aa';
  static const cudaRuntimeUrl =
      'https://developer.download.nvidia.com/compute/cuda/redist/cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-12.8.90-archive.zip';
  static const cudaRuntimeSha =
      '4a39058fd8519444a81cfc7ae055d136f48d1a31ffa41ae255b35b2edd61e13b';
  static const iosModelUrl =
      'https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip';
  static const iosModelSha =
      '49a6ac1f62e12a2b3e426730d686fa466e30cba11c03b85305775714fb9814ec';

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> install(void Function(String) status) async {
    _cancelled = false;
    _client = HttpClient();
    try {
      if (Platform.isWindows) {
        if (await findWindowsRuntime(root) == null) {
          final zip = await _download(
            windowsRuntimeUrl,
            '$root/runtime/sd-cuda.zip',
            expectedBytes: 333462536,
            sha256Hex: windowsRuntimeSha,
            status: status,
          );
          status('Installing the local image runtime…');
          await Isolate.run(() => extractFileToDisk(zip, '$root/runtime'));
          if (await findWindowsRuntime(root) == null) {
            throw StateError(
              'The image runtime archive did not contain sd-cli.exe.',
            );
          }
        }
        await _installCudaLibraries(status);
        final model = File('$root/models/v1-5-pruned-emaonly.safetensors');
        await _download(
          windowsModelUrl,
          model.path,
          expectedBytes: 4265146304,
          sha256Hex: windowsModelSha,
          status: status,
        );
      } else if (Platform.isIOS) {
        if (await findCoreMLResources(root) == null) {
          final zip = await _download(
            iosModelUrl,
            '$root/coreml/coreml-sd15-split.zip',
            expectedBytes: 1565721769,
            sha256Hex: iosModelSha,
            status: status,
          );
          status('Installing the local iPhone image model…');
          await Isolate.run(() => extractFileToDisk(zip, '$root/coreml'));
          if (await findCoreMLResources(root) == null) {
            throw StateError(
              'The image model is missing the files needed for photo editing.',
            );
          }
        }
      } else {
        throw UnsupportedError(
          'Image Studio currently supports Windows and iOS.',
        );
      }
    } finally {
      _client?.close();
      _client = null;
    }
  }

  Future<void> _installCudaLibraries(void Function(String) status) async {
    // The CPU backend still works on PCs without an NVIDIA card.
    try {
      final gpu = await Process.run('nvidia-smi', ['-L']);
      if (gpu.exitCode != 0) return;
    } on ProcessException {
      return;
    }
    final required = [
      'cublas64_12.dll',
      'cublasLt64_12.dll',
      'cudart64_12.dll',
    ];
    final installed = await Future.wait(
      required.map((name) => File('$root/runtime/$name').exists()),
    );
    if (installed.every((exists) => exists)) {
      return;
    }
    for (final item in [
      (url: cudaBlasUrl, file: 'cublas.zip', size: 563660944, sha: cudaBlasSha),
      (
        url: cudaRuntimeUrl,
        file: 'cudart.zip',
        size: 3037735,
        sha: cudaRuntimeSha,
      ),
    ]) {
      final zip = await _download(
        item.url,
        '$root/runtime/${item.file}',
        expectedBytes: item.size,
        sha256Hex: item.sha,
        status: status,
      );
      status('Installing NVIDIA image acceleration…');
      await Isolate.run(
        () => extractFileToDisk(zip, '$root/runtime/cuda-deps'),
      );
    }
    final dependencies = Directory('$root/runtime/cuda-deps');
    await for (final entry in dependencies.list(recursive: true)) {
      if (entry is File && required.contains(entry.uri.pathSegments.last)) {
        await entry.copy('$root/runtime/${entry.uri.pathSegments.last}');
      }
    }
    if (!(await Future.wait(
      required.map((name) => File('$root/runtime/$name').exists()),
    )).every((exists) => exists)) {
      throw StateError('NVIDIA runtime files were missing after extraction.');
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
