import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/reply_quality.dart';

void main() {
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
}
