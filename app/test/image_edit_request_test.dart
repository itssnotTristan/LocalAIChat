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
        modelDirectory: 'not-used',
        prompt: 'remove my shirt',
        strength: 0.30,
        steps: 20,
        seed: 1,
      ),
      throwsUnsupportedError,
    );
  });

  test('ordinary edits remain available', () {
    expect(unsupportedImageEdit('warm the lighting'), isNull);
    expect(unsupportedImageEdit('change the background to a garden'), isNull);
    expect(unsupportedImageEdit('make my blue shirt red'), isNull);
    expect(unsupportedImageEdit('brighten this nude photo'), isNull);
    expect(unsupportedImageEdit('put my nude portrait in a forest'), isNull);
  });

  test('forest edits use a whole-image prompt instead of a scene cutout', () {
    const prompt = 'make the background look like I am outside in a forest';
    expect(isBackgroundReplacement(prompt), isTrue);
    final instruction = wholeImageEditPrompt(prompt);
    expect(instruction, contains(prompt));
    expect(instruction, contains('same subject'));
    expect(instruction, contains('No pasted cutout'));
    expect(
      isBackgroundReplacement('change the background to a garden'),
      isTrue,
    );
    expect(wholeImageEditPrompt('put me in a forest'), contains('a forest'));
    expect(
      wholeImageEditPrompt('make it look like I am outdoors'),
      contains('outdoors'),
    );
    expect(isBackgroundReplacement('make the lighting warmer'), isFalse);
  });
}
