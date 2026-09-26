import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/image_edit_request.dart';
import 'package:local_ai_chat/image_studio_engine.dart';

void main() {
  test('clothing removal request is stopped before model execution', () async {
    expect(unsupportedImageEdit('remove my shirt'), isNotNull);
    expect(unsupportedImageEdit('make her naked'), isNotNull);
    expect(unsupportedImageEdit('take off the jacket'), isNotNull);
    final engine = ImageStudioEngine(root: 'not-used');
    await expectLater(
      engine.edit(
        inputPath: 'not-used.jpg',
        prompt: 'remove my shirt',
        strength: 0.30,
        steps: 20,
        seed: 1,
        width: 512,
        height: 512,
      ),
      throwsUnsupportedError,
    );
  });

  test('ordinary edits remain available', () {
    expect(unsupportedImageEdit('warm the lighting'), isNull);
    expect(unsupportedImageEdit('change the background to a garden'), isNull);
    expect(unsupportedImageEdit('make my blue shirt red'), isNull);
  });

  test('routes forest background edits without requesting another person', () {
    const prompt = 'make the background look like I am outside in a forest';
    expect(isBackgroundReplacement(prompt), isTrue);
    final scene = backgroundScenePrompt(prompt);
    expect(scene, contains('outside in a forest'));
    expect(scene, isNot(contains('I am')));
    expect(scene, contains('empty scenery'));
    expect(
      isBackgroundReplacement('change the background to a garden'),
      isTrue,
    );
    expect(backgroundScenePrompt('put me in a forest'), contains('a forest'));
    expect(
      backgroundScenePrompt('make it look like I am outdoors'),
      contains('outdoors'),
    );
    expect(isBackgroundReplacement('make the lighting warmer'), isFalse);
  });
}
