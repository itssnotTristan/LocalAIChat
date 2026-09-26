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

  test('keeps the first thought when the model restarts it three times', () {
    const answer =
        'That looks like a fun scene, and I can see why it caught your eye. '
        "I'm already imagining a playful conversation about the evening. "
        'There is a window and a blue lamp nearby. '
        "I'm already imagining a different ending to the story. "
        'The person turns toward the camera for a moment. '
        "I'm already imagining one more thing to say.";
    final start = repetitivePhraseStart(answer);
    expect(start, isNotNull);
    expect(
      answer.substring(0, start!).trimRight(),
      contains('blue lamp nearby.'),
    );
    expect(answer.substring(0, start), isNot(contains('a different ending')));
  });

  test('does not cut a natural second mention of the same subject', () {
    const answer =
        'The blue lamp is on the table beside a book. '
        'I like how the blue lamp makes the room feel cozy. '
        'The person smiles and moves the book to the shelf.';
    expect(repetitivePhraseStart(answer), isNull);
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
