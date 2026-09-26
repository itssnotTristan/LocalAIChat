import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import 'image_studio_engine.dart';

class InstalledImageModel {
  const InstalledImageModel({
    required this.id,
    required this.name,
    required this.directory,
    required this.isBuiltIn,
  });

  final String id;
  final String name;
  final String directory;
  final bool isBuiltIn;
}

/// Manages only model copies inside Image Studio's private app directory.
class ImageStudioModels {
  ImageStudioModels(this.root);

  static const builtInId = 'realistic-vision-5.1';
  final String root;

  String get _coreml => '$root/coreml';
  String get _builtIn => '$_coreml/$builtInId';
  String get _custom => '$_coreml/custom';
  File get _selection => File('$_coreml/selected-model.txt');

  Future<List<InstalledImageModel>> installed() async {
    final result = <InstalledImageModel>[];
    final builtInResources = await findCoreMLResourcesAt(
      _builtIn,
      requiredFiles: coreMLResourceSizes,
    );
    if (builtInResources != null) {
      result.add(
        InstalledImageModel(
          id: builtInId,
          name: await _displayName(_builtIn, 'Realistic Vision 5.1'),
          directory: builtInResources,
          isBuiltIn: true,
        ),
      );
    }
    final folder = Directory(_custom);
    if (await folder.exists()) {
      await for (final entry in folder.list()) {
        if (entry is! Directory) continue;
        final id = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
        if (!RegExp(r'^custom-[0-9]+$').hasMatch(id)) continue;
        final resources = await findCompatibleCoreMLResources(entry.path);
        if (resources == null) continue;
        result.add(
          InstalledImageModel(
            id: id,
            name: await _displayName(entry.path, 'Imported image model'),
            directory: resources,
            isBuiltIn: false,
          ),
        );
      }
    }
    return result;
  }

  Future<InstalledImageModel?> selected() async {
    final models = await installed();
    if (models.isEmpty) return null;
    final id = await _selection.exists()
        ? (await _selection.readAsString()).trim()
        : '';
    for (final model in models) {
      if (model.id == id) return model;
    }
    return models.first;
  }

  Future<void> select(String id) async {
    if (!(await installed()).any((model) => model.id == id)) {
      throw StateError('That image model is not installed.');
    }
    await _selection.parent.create(recursive: true);
    await _selection.writeAsString(id, flush: true);
  }

  Future<void> rename(String id, String name) async {
    final model = (await installed())
        .where((item) => item.id == id)
        .firstOrNull;
    if (model == null) throw StateError('That image model is not installed.');
    final cleaned = name.replaceAll(RegExp(r'[\r\n\x00-\x1f]'), ' ').trim();
    if (cleaned.isEmpty || cleaned.length > 60) {
      throw ArgumentError('Choose a model name from 1 to 60 characters.');
    }
    final folder = model.isBuiltIn ? _builtIn : '$_custom/$id';
    await File('$folder/name.txt').writeAsString(cleaned, flush: true);
  }

  Future<void> delete(String id) async {
    final model = (await installed())
        .where((item) => item.id == id)
        .firstOrNull;
    if (model == null) throw StateError('That image model is not installed.');
    final folder = model.isBuiltIn ? _builtIn : '$_custom/$id';
    await Directory(folder).delete(recursive: true);
    if (model.isBuiltIn) {
      final zip = File('$_coreml/realistic-vision-5.1.zip');
      if (await zip.exists()) await zip.delete();
    }
    final next = await selected();
    if (next == null) {
      if (await _selection.exists()) await _selection.delete();
    } else {
      await select(next.id);
    }
  }

  /// Import a ZIP made for Apple's ml-stable-diffusion Swift pipeline.
  /// It must contain a VAE encoder to support editing an existing photo.
  Future<InstalledImageModel> importZip(
    String sourcePath,
    String displayName,
    void Function(String) status,
  ) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Core ML image models can be imported on iPhone.');
    }
    final source = File(sourcePath);
    if (!await source.exists())
      throw StateError('The ZIP is no longer available.');
    if (await source.length() > 4 * 1024 * 1024 * 1024) {
      throw StateError('Choose a Core ML model ZIP smaller than 4 GiB.');
    }
    status('Checking the model ZIP…');
    await Isolate.run(() => validateImageModelZip(sourcePath));
    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    final folder = Directory('$_custom/$id');
    await folder.create(recursive: true);
    try {
      final copy = await source.copy('${folder.path}/model.zip');
      status('Importing Core ML image model…');
      await Isolate.run(
        () => extractFileToDisk(copy.path, '${folder.path}/files'),
      );
      final resources = await findCompatibleCoreMLResources(folder.path);
      if (resources == null) {
        throw StateError(
          'This ZIP needs compiled TextEncoder, UNet, VAE encoder and decoder, vocab.json, and merges.txt files.',
        );
      }
      status(
        'Model files imported. The first edit will test loading on this iPhone.',
      );
      final cleanedName = displayName
          .replaceAll(RegExp(r'[\r\n\x00-\x1f]'), ' ')
          .trim();
      await File('${folder.path}/name.txt').writeAsString(
        cleanedName.isEmpty
            ? 'Imported image model'
            : (cleanedName.length > 60
                  ? cleanedName.substring(0, 60)
                  : cleanedName),
        flush: true,
      );
      await copy.delete();
      await select(id);
      return (await installed()).firstWhere((model) => model.id == id);
    } catch (_) {
      if (await folder.exists()) await folder.delete(recursive: true);
      rethrow;
    }
  }

  Future<String> _displayName(String folder, String fallback) async {
    final file = File('$folder/name.txt');
    if (!await file.exists()) return fallback;
    final name = (await file.readAsString()).trim();
    return name.isEmpty ? fallback : name;
  }
}

/// Checks the ZIP directory before extraction. The archive package also
/// confines extraction to the destination, but rejecting unsafe entries is
/// clearer and avoids writing a partial model.
Future<void> validateImageModelZip(String path) async {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    var total = 0;
    var entries = 0;
    for (final entry in archive) {
      entries++;
      final name = entry.name.replaceAll('\\', '/');
      final parts = name.split('/');
      if (name.startsWith('/') ||
          name.contains(':') ||
          parts.contains('..') ||
          entry.isSymbolicLink) {
        throw StateError('The ZIP contains an unsafe file path.');
      }
      total += entry.size;
      if (entries > 300 || total > 6 * 1024 * 1024 * 1024) {
        throw StateError('This model ZIP is too large to import on iPhone.');
      }
    }
    if (entries < 8)
      throw StateError('This ZIP does not contain a full Core ML image model.');
    await archive.clear();
  } finally {
    await input.close();
  }
}
