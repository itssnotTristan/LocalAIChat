import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'model_download.dart';
import 'image_studio_install.dart';

class BackgroundModelFile {
  const BackgroundModelFile(
    this.name,
    this.baseUrl,
    this.sha256Hex, {
    this.expectedBytes = 0,
  });

  final String name;
  final String baseUrl;
  final String sha256Hex;
  final int expectedBytes;
}

class BackgroundModelPack {
  const BackgroundModelPack(
    this.id,
    this.name,
    this.files, {
    this.projectorName,
  });

  final String id;
  final String name;
  final List<BackgroundModelFile> files;
  final String? projectorName;

  String get modelName => files.first.name;

  static const all = <BackgroundModelPack>[
    BackgroundModelPack('everyday', 'Ministral 3B · everyday chat', [
      BackgroundModelFile(
        ModelDownloader.everydayName,
        ModelDownloader.everydayUrl,
        ModelDownloader.everydaySha256,
        expectedBytes: ModelDownloader.everydayBytes,
      ),
    ]),
    BackgroundModelPack('starter', 'SmolVLM2 500M Video Q8', [
      BackgroundModelFile(
        ModelDownloader.modelName,
        ModelDownloader.base,
        ModelDownloader.modelSha256,
      ),
      BackgroundModelFile(
        ModelDownloader.projectorName,
        ModelDownloader.base,
        ModelDownloader.projectorSha256,
      ),
    ], projectorName: ModelDownloader.projectorName),
    BackgroundModelPack('detailed', 'Qwen3.5 4B Uncensored · vision', [
      BackgroundModelFile(
        ModelDownloader.detailedVisionName,
        ModelDownloader.detailedVisionUrl,
        ModelDownloader.detailedVisionSha256,
      ),
      BackgroundModelFile(
        ModelDownloader.detailedProjectorName,
        ModelDownloader.detailedVisionUrl,
        ModelDownloader.detailedProjectorSha256,
      ),
    ], projectorName: ModelDownloader.detailedProjectorName),
    BackgroundModelPack('adult-vision', 'Qwen3 VL 4B Abliterated · vision', [
      BackgroundModelFile(
        ModelDownloader.adultVisionName,
        ModelDownloader.adultVisionUrl,
        ModelDownloader.adultVisionSha256,
        expectedBytes: ModelDownloader.adultVisionBytes,
      ),
      BackgroundModelFile(
        ModelDownloader.adultProjectorName,
        ModelDownloader.adultVisionUrl,
        ModelDownloader.adultProjectorSha256,
        expectedBytes: ModelDownloader.adultProjectorBytes,
      ),
    ], projectorName: ModelDownloader.adultProjectorName),
    BackgroundModelPack('roleplay', 'Nymphaea 4B · adult roleplay', [
      BackgroundModelFile(
        ModelDownloader.roleplayName,
        ModelDownloader.roleplayUrl,
        ModelDownloader.roleplaySha256,
        expectedBytes: ModelDownloader.roleplayBytes,
      ),
    ]),
  ];

  static BackgroundModelPack byId(String id) =>
      all.firstWhere((pack) => pack.id == id);
}

class BackgroundTransferStatus {
  const BackgroundTransferStatus({
    required this.id,
    required this.state,
    required this.received,
    required this.expected,
    required this.error,
  });

  final String id;
  final String state;
  final int received;
  final int expected;
  final String error;

  factory BackgroundTransferStatus.fromMap(Map<dynamic, dynamic> value) =>
      BackgroundTransferStatus(
        id: value['id'] as String? ?? '',
        state: value['state'] as String? ?? '',
        received: (value['received'] as num?)?.toInt() ?? 0,
        expected: (value['expected'] as num?)?.toInt() ?? 0,
        error: value['error'] as String? ?? '',
      );
}

/// The native iOS URLSession keeps transferring after Flutter is suspended.
/// Files become selectable only after this class checks publisher SHA-256.
class BackgroundModelDownloads {
  static const _channel = MethodChannel('local_ai_chat/model_transfers');
  static const imageArchiveTaskId = 'image-realistic-vision-5.1';
  final _verifiedPaths = <String>{};

  String taskId(BackgroundModelPack pack, BackgroundModelFile file) =>
      '${pack.id}-${file.name}';

  Future<void> queueImageArchive(String root) async {
    if (!Platform.isIOS) throw UnsupportedError('Background models need iOS.');
    await Directory('$root/coreml').create(recursive: true);
    await _channel.invokeMethod<void>('start', {
      'id': imageArchiveTaskId,
      'url': ImageStudioInstaller.iosModelUrl,
      'destination': '$root/coreml/realistic-vision-5.1.zip.part',
      'expected': 916522756,
    });
  }

  Future<void> queue(String root, BackgroundModelPack pack) async {
    if (!Platform.isIOS) throw UnsupportedError('Background models need iOS.');
    final folder = Directory('$root/models');
    await folder.create(recursive: true);
    for (final file in pack.files) {
      final finalFile = File('${folder.path}/${file.name}');
      if (await finalFile.exists() &&
          (await sha256.bind(finalFile.openRead()).first).toString() ==
              file.sha256Hex) {
        _verifiedPaths.add(finalFile.path);
        continue;
      }
      await _channel.invokeMethod<void>('start', {
        'id': taskId(pack, file),
        'url': '${file.baseUrl}${file.name}',
        'destination': '${finalFile.path}.part',
        'expected': file.expectedBytes,
      });
    }
  }

  Future<List<BackgroundTransferStatus>> statuses() async {
    if (!Platform.isIOS) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('list') ?? [];
    return raw.whereType<Map>().map(BackgroundTransferStatus.fromMap).toList();
  }

  Future<void> cancel(String id) =>
      _channel.invokeMethod<void>('cancel', {'id': id});

  Future<void> forgetId(String id) =>
      _channel.invokeMethod<void>('forget', {'id': id});

  /// Returns packs whose every file is downloaded and checksum verified.
  /// A queued file is never registered as a usable model before this succeeds.
  Future<List<BackgroundModelPack>> finalize(
    String root,
    List<BackgroundTransferStatus> statuses,
  ) async {
    final byId = {for (final item in statuses) item.id: item};
    final ready = <BackgroundModelPack>[];
    for (final pack in BackgroundModelPack.all) {
      if (!pack.files.any((file) => byId.containsKey(taskId(pack, file)))) {
        continue;
      }
      var complete = true;
      for (final file in pack.files) {
        final target = File('$root/models/${file.name}');
        final partial = File('${target.path}.part');
        final transfer = byId[taskId(pack, file)];
        if (transfer != null &&
            transfer.state != 'downloaded' &&
            !_verifiedPaths.contains(target.path)) {
          complete = false;
          break;
        }
        final candidate = await partial.exists() ? partial : target;
        if (!await candidate.exists()) {
          complete = false;
          break;
        }
        if (!_verifiedPaths.contains(candidate.path)) {
          final actual = (await sha256.bind(candidate.openRead()).first)
              .toString();
          if (actual != file.sha256Hex) {
            await candidate.delete();
            await _channel.invokeMethod<void>('forget', {
              'id': taskId(pack, file),
            });
            throw StateError(
              '${file.name} failed SHA-256. Retry this download.',
            );
          }
          _verifiedPaths.add(candidate.path);
        }
        if (candidate.path == partial.path) {
          if (await target.exists()) await target.delete();
          await partial.rename(target.path);
          _verifiedPaths.add(target.path);
        }
      }
      if (complete) ready.add(pack);
    }
    return ready;
  }

  Future<void> forget(BackgroundModelPack pack) async {
    for (final file in pack.files) {
      await _channel.invokeMethod<void>('forget', {'id': taskId(pack, file)});
    }
  }
}
