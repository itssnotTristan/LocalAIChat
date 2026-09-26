import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/reply_quality.dart';

void main() {
  test('catches exact echo and unsupported visual claim', () {
    expect(
      isEchoedReply(
        'Do you want to see my penis?',
        'do you want to see my penis',
      ),
      isTrue,
    );
    expect(
      isEchoedReply('Yes, you can share it.', 'Do you want to see it?'),
      isFalse,
    );
    expect(
      isDetachedMediaReply(
        'A visible object in the image/frame.',
        'Do you want to see it?',
      ),
      isTrue,
    );
    expect(
      isDetachedMediaReply('The image shows a dog.', 'What is in the image?'),
      isFalse,
    );
  });
  test('hides complete and streaming thinking blocks', () {
    expect(
      visibleReply('<think>private notes</think>Hello there.'),
      'Hello there.',
    );
    expect(visibleReply('<think>still writing'), '');
  });

  test('detects a phrase loop without flagging a short answer', () {
    expect(isRepeatingReply('Hello there.'), isFalse);
    expect(
      isRepeatingReply(
        'I can help describe the scene directly and answer your question. '
        'The room has a bed and a window in the background. '
        'The room has a bed and a window in the background.',
      ),
      isTrue,
    );
  });

  test('cuts a changing-word anatomy loop at its first sentence', () {
    const lead = 'A woman is on a bed and turns toward the camera. ';
    const loop =
        'She has a small mouth. She has a small nose. '
        'She has a small chin. She has a small jaw.';
    final start = repetitiveSentenceRunStart(lead + loop);
    expect(start, isNotNull);
    expect((lead + loop).substring(0, start!).trimRight(), lead.trimRight());
  });

  test('keeps normal descriptions with varied sentence structure', () {
    expect(
      repetitiveSentenceRunStart(
        'She turns to the camera. The bed has a gray cover. '
        'Her black top is pulled up. She moves out of view.',
      ),
      isNull,
    );
  });
}
