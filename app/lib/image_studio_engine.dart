import 'dart:io';

import 'package:flutter/services.dart';

/// A photo edit keeps its input and writes a separate output file. No image is
/// sent to a server: Windows runs sd-cli, and iOS uses the Core ML bridge.
class ImageStudioEngine {
  ImageStudioEngine({required this.root});

  final String root;
  Process? _running;

  Future<String> edit({
    required String inputPath,
    required String prompt,
    required double strength,
    required int steps,
    required int seed,
    required int width,
    required int height,
    void Function(String)? onStatus,
  }) async {
    if (prompt.trim().isEmpty) throw ArgumentError('Describe the edit first.');
    if (!await File(inputPath).exists()) {
      throw StateError('The selected photo is missing.');
    }
    final outputDir = Directory('$root${Platform.pathSeparator}outputs');
    await outputDir.create(recursive: true);
    final outputPath =
        '${outputDir.path}${Platform.pathSeparator}edit_${DateTime.now().microsecondsSinceEpoch}.png';
    if (Platform.isIOS) {
      final modelDirectory = await findCoreMLResources(root);
      if (modelDirectory == null) {
        throw StateError('Install the local iPhone image model first.');
      }
      onStatus?.call('Editing on this iPhone…');
      final result = await const MethodChannel('local_ai_chat/image_studio')
          .invokeMethod<String>('editImage', {
            'input': inputPath,
            'output': outputPath,
            'modelDirectory': modelDirectory,
            'prompt': prompt.trim(),
            'strength': strength,
            'steps': steps,
            'seed': seed,
          });
      if (result == null || !await File(result).exists()) {
        throw StateError('The iPhone image model did not save an edit.');
      }
      return result;
    }
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Image Studio currently supports Windows and iOS.',
      );
    }
    final executable = await findWindowsRuntime(root);
    if (executable == null) {
      throw StateError('Install the local image editor runtime first.');
    }
    final model = File('$root/models/v1-5-pruned-emaonly.safetensors');
    if (!await model.exists()) {
      throw StateError('Install the local image editing model first.');
    }
    onStatus?.call('Editing on this PC…');
    final process = await Process.start(
      executable,
      sdCliArguments(
        model: model.path,
        input: inputPath,
        output: outputPath,
        prompt: prompt.trim(),
        strength: strength,
        steps: steps,
        seed: seed,
        width: width,
        height: height,
      ),
      workingDirectory: File(executable).parent.path,
    );
    _running = process;
    final stderr = StringBuffer();
    final output = process.stdout.drain<void>();
    final errors = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((line) {
          if (stderr.length < 4000) stderr.write(line);
        });
    try {
      final code = await process.exitCode;
      await output;
      await errors.cancel();
      if (code != 0 || !await File(outputPath).exists()) {
        throw StateError(
          'Local image edit failed (code $code). ${stderr.toString().trim()}',
        );
      }
      return outputPath;
    } finally {
      _running = null;
    }
  }

  void cancel() {
    _running?.kill();
    if (Platform.isIOS) {
      const MethodChannel('local_ai_chat/image_studio')
          .invokeMethod<void>('cancelEdit');
    }
  }
}

List<String> sdCliArguments({
  required String model,
  required String input,
  required String output,
  required String prompt,
  required double strength,
  required int steps,
  required int seed,
  required int width,
  required int height,
}) => [
  '-m',
  model,
  '-i',
  input,
  '-o',
  output,
  '-p',
  prompt,
  '--strength',
  strength.toStringAsFixed(2),
  '--steps',
  '$steps',
  '--cfg-scale',
  '7',
  '--seed',
  '$seed',
  '-W',
  '$width',
  '-H',
  '$height',
  '--vae-tiling',
  '--image-preprocess',
  'target=init,mode=fit-pad,pad_color=#202020',
];

Future<String?> findWindowsRuntime(String root) async {
  final runtime = Directory('$root/runtime');
  if (!await runtime.exists()) return null;
  await for (final entry in runtime.list(recursive: true)) {
    if (entry is File && entry.path.toLowerCase().endsWith('sd-cli.exe')) {
      return entry.path;
    }
  }
  return null;
}

const coreMLResourceSizes = <String, int>{
  'vocab.json': 862328,
  'merges.txt': 524657,
  'TextEncoder.mlmodelc/coremldata.bin': 825,
  'TextEncoder.mlmodelc/model.mil': 208229,
  'TextEncoder.mlmodelc/weights/weight.bin': 139866304,
  'Unet.mlmodelc/coremldata.bin': 1207,
  'Unet.mlmodelc/model.mil': 3040467,
  'Unet.mlmodelc/weights/weight.bin': 645167616,
  'VAEDecoder.mlmodelc/coremldata.bin': 755,
  'VAEDecoder.mlmodelc/model.mil': 181386,
  'VAEDecoder.mlmodelc/weights/weight.bin': 98993280,
  'VAEEncoder.mlmodelc/coremldata.bin': 761,
  'VAEEncoder.mlmodelc/model.mil': 139736,
  'VAEEncoder.mlmodelc/weights/weight.bin': 68338112,
};

Future<String?> findCoreMLResources(
  String root, {
  Map<String, int> requiredFiles = coreMLResourceSizes,
}) async {
  final folder = Directory('$root/coreml');
  if (!await folder.exists()) return null;
  await for (final entry in folder.list(recursive: true)) {
    if (entry is File && entry.path.endsWith('vocab.json')) {
      final candidate = entry.parent.path;
      var complete = true;
      for (final item in requiredFiles.entries) {
        final file = File('$candidate/${item.key}');
        if (!await file.exists() || await file.length() != item.value) {
          complete = false;
          break;
        }
      }
      if (complete &&
          await Directory('$candidate/VAEEncoder.mlmodelc').exists() &&
          await Directory('$candidate/VAEDecoder.mlmodelc').exists() &&
          await Directory('$candidate/Unet.mlmodelc').exists()) {
        return candidate;
      }
    }
  }
  return null;
}
