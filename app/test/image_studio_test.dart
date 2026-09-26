import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/image_studio_engine.dart';

void main() {
  test('iPhone model is considered ready only with an image encoder', () async {
    final root = await Directory.systemTemp.createTemp('image_studio_model_');
    addTearDown(() => root.delete(recursive: true));
    final resources = Directory('${root.path}/coreml/model');
    await resources.create(recursive: true);
    await File('${resources.path}/vocab.json').writeAsString('{}');
    await Directory('${resources.path}/TextEncoder.mlmodelc').create();
    await Directory('${resources.path}/VAEDecoder.mlmodelc').create();
    await Directory('${resources.path}/Unet.mlmodelc').create();
    final requiredFiles = <String, int>{'vocab.json': 2};
    expect(
      await findCoreMLResources(root.path, requiredFiles: requiredFiles),
      isNull,
    );
    await Directory('${resources.path}/VAEEncoder.mlmodelc').create();
    expect(
      await Directory(
        (await findCoreMLResources(root.path, requiredFiles: requiredFiles))!,
      ).resolveSymbolicLinks(),
      await resources.resolveSymbolicLinks(),
    );
  });
}
