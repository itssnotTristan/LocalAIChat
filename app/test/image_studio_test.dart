import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/image_studio_engine.dart';

void main() {
  test(
    'image edits use the chosen source and keep the full photo in frame',
    () {
      final args = sdCliArguments(
        model: r'D:\models\editor.safetensors',
        input: r'D:\photos\source.png',
        output: r'D:\edits\result.png',
        prompt: 'warm sunset lighting',
        strength: 0.45,
        steps: 20,
        seed: 23,
        width: 512,
        height: 512,
      );
      expect(args[args.indexOf('-i') + 1], r'D:\photos\source.png');
      expect(args[args.indexOf('-o') + 1], r'D:\edits\result.png');
      expect(args[args.indexOf('--strength') + 1], '0.45');
      expect(args[args.indexOf('--steps') + 1], '20');
      expect(
        args[args.indexOf('--image-preprocess') + 1],
        contains('mode=fit-pad'),
      );
    },
  );

  test('iPhone model is considered ready only with an image encoder', () async {
    final root = await Directory.systemTemp.createTemp('image_studio_model_');
    addTearDown(() => root.delete(recursive: true));
    final resources = Directory('${root.path}/coreml/model');
    await resources.create(recursive: true);
    await File('${resources.path}/vocab.json').writeAsString('{}');
    await Directory('${resources.path}/VAEDecoder.mlmodelc').create();
    await Directory('${resources.path}/Unet.mlmodelc').create();
    expect(await findCoreMLResources(root.path), isNull);
    await Directory('${resources.path}/VAEEncoder.mlmodelc').create();
    expect(
      await Directory((await findCoreMLResources(root.path))!)
          .resolveSymbolicLinks(),
      await resources.resolveSymbolicLinks(),
    );
  });
}
