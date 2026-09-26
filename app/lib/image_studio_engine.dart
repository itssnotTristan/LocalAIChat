import 'dart:io';

import 'package:flutter/services.dart';

import 'image_edit_request.dart';

/// A photo edit keeps its input and writes a separate output file. No image is
/// sent to a server: iOS uses Core ML and Vision.
class ImageStudioEngine {
  ImageStudioEngine({required this.root});

  final String root;

  Future<String> edit({
    required String inputPath,
    required String modelDirectory,
    required String prompt,
    required double strength,
    required int steps,
    required int seed,
    void Function(String)? onStatus,
  }) async {
    if (prompt.trim().isEmpty) throw ArgumentError('Describe the edit first.');
    final unsupported = unsupportedImageEdit(prompt);
    if (unsupported != null) throw UnsupportedError(unsupported);
    if (!await File(inputPath).exists()) {
      throw StateError('The selected photo is missing.');
    }
    final outputDir = Directory('$root${Platform.pathSeparator}outputs');
    await outputDir.create(recursive: true);
    final outputPath =
        '${outputDir.path}${Platform.pathSeparator}edit_${DateTime.now().microsecondsSinceEpoch}.png';
    if (Platform.isIOS) {
      if (await findCompatibleCoreMLResources(modelDirectory) == null) {
        throw StateError('Choose an installed iPhone image model first.');
      }
      onStatus?.call('Redrawing the entire photo on this iPhone…');
      final result = await const MethodChannel('local_ai_chat/image_studio')
          .invokeMethod<String>('editImage', {
            'input': inputPath,
            'output': outputPath,
            'modelDirectory': modelDirectory,
            'prompt': wholeImageEditPrompt(prompt),
            'strength': strength,
            'steps': steps,
            'seed': seed,
          });
      if (result == null || !await File(result).exists()) {
        throw StateError('The iPhone image model did not save an edit.');
      }
      return result;
    }
    throw UnsupportedError('Image Studio is available on iPhone.');
  }

  void cancel() {
    if (Platform.isIOS) {
      const MethodChannel('local_ai_chat/image_studio')
          .invokeMethod<void>('cancelEdit');
    }
  }
}

const coreMLResourceSizes = <String, int>{
  'vocab.json': 862328,
  'merges.txt': 524657,
  'TextEncoder.mlmodelc/coremldata.bin': 968,
  'TextEncoder.mlmodelc/model.mil': 185810,
  'TextEncoder.mlmodelc/weights/weight.bin': 139910080,
  'Unet.mlmodelc/coremldata.bin': 1401,
  'Unet.mlmodelc/model.mil': 3136990,
  'Unet.mlmodelc/weights/weight.bin': 645325440,
  'VAEDecoder.mlmodelc/coremldata.bin': 895,
  'VAEDecoder.mlmodelc/model.mil': 194901,
  'VAEDecoder.mlmodelc/weights/weight.bin': 98993280,
  'VAEEncoder.mlmodelc/coremldata.bin': 899,
  'VAEEncoder.mlmodelc/model.mil': 149284,
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
      if (await _hasCoreMLResources(candidate, requiredFiles)) return candidate;
    }
  }
  return null;
}

Future<String?> findCoreMLResourcesAt(
  String folder, {
  Map<String, int> requiredFiles = coreMLResourceSizes,
}) async {
  final base = Directory(folder);
  if (!await base.exists()) return null;
  await for (final entry in base.list(recursive: true, followLinks: false)) {
    if (entry is File && entry.path.endsWith('vocab.json')) {
      final candidate = entry.parent.path;
      if (await _hasCoreMLResources(candidate, requiredFiles)) return candidate;
    }
  }
  return null;
}

Future<String?> findCompatibleCoreMLResources(String folder) async {
  final base = Directory(folder);
  if (!await base.exists()) return null;
  await for (final entry in base.list(recursive: true, followLinks: false)) {
    if (entry is File && entry.path.endsWith('vocab.json')) {
      final candidate = entry.parent.path;
      var complete = true;
      for (final name in [
        'vocab.json',
        'merges.txt',
        'TextEncoder.mlmodelc/coremldata.bin',
        'Unet.mlmodelc/coremldata.bin',
        'VAEEncoder.mlmodelc/coremldata.bin',
        'VAEDecoder.mlmodelc/coremldata.bin',
      ]) {
        final file = File('$candidate/$name');
        if (!await file.exists() || await file.length() == 0) {
          complete = false;
          break;
        }
      }
      if (complete) return candidate;
    }
  }
  return null;
}

Future<bool> _hasCoreMLResources(
  String folder,
  Map<String, int> requiredFiles,
) async {
  for (final name in [
    'TextEncoder.mlmodelc',
    'Unet.mlmodelc',
    'VAEDecoder.mlmodelc',
    'VAEEncoder.mlmodelc',
  ]) {
    if (!await Directory('$folder/$name').exists()) return false;
  }
  for (final item in requiredFiles.entries) {
    final file = File('$folder/${item.key}');
    if (!await file.exists() || await file.length() != item.value) return false;
  }
  return true;
}
