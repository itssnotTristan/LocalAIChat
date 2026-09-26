import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/image_studio_models.dart';

void main() {
  test('custom image model can be selected, renamed, and deleted', () async {
    final root = await Directory.systemTemp.createTemp('image_model_manager_');
    addTearDown(() => root.delete(recursive: true));
    final resources = Directory(
      '${root.path}/coreml/custom/custom-123/files/Resources',
    );
    await resources.create(recursive: true);
    for (final name in [
      'vocab.json',
      'merges.txt',
      'TextEncoder.mlmodelc/coremldata.bin',
      'Unet.mlmodelc/coremldata.bin',
      'VAEEncoder.mlmodelc/coremldata.bin',
      'VAEDecoder.mlmodelc/coremldata.bin',
    ]) {
      final file = File('${resources.path}/$name');
      await file.parent.create(recursive: true);
      await file.writeAsString('model');
    }
    final manager = ImageStudioModels(root.path);
    expect((await manager.installed()).single.id, 'custom-123');
    await manager.select('custom-123');
    expect((await manager.selected())?.id, 'custom-123');
    await manager.rename('custom-123', 'My photo model');
    expect((await manager.selected())?.name, 'My photo model');
    await manager.delete('custom-123');
    expect(await manager.installed(), isEmpty);
    expect(await manager.selected(), isNull);
    expect(
      await File('${root.path}/coreml/selected-model.txt').exists(),
      isFalse,
    );
  });
}
