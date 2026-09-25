import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/chat_context.dart';
import 'package:local_ai_chat/main.dart';

void main() {
  test('personality and memory persist per conversation', () {
    final first = Conversation(
      'one',
      'Roleplay',
      [],
      'Jerk',
      '',
      'The user likes green tea.',
    );
    final second = Conversation('two', 'Normal');
    final restored = Conversation.fromJson(first.toJson());
    expect(restored.personality, 'Jerk');
    expect(restored.memory, 'The user likes green tea.');
    expect(second.personality, 'Default');
    expect(second.memory, isEmpty);
    final prompt = ChatContext.instructions(
      global: 'Answer directly.',
      personality: restored.personality,
      customPersonality: restored.customPersonality,
      memory: restored.memory,
    );
    expect(prompt, contains('rude, sarcastic jerk'));
    expect(prompt, contains('green tea'));
  });

  test('explicit memory can be updated after a correction', () {
    var memory = ChatContext.addMemory(
      '',
      ChatContext.explicitMemory('Remember that my favorite color is red.')!,
    );
    memory = ChatContext.addMemory(
      memory,
      ChatContext.explicitMemory('Correction: my favorite color is green.')!,
    );
    expect(memory, contains('green'));
    expect(memory, isNot(contains('red')));
    expect(ChatContext.explicitMemory('Hi'), isNull);
  });

  test(
    'media corrections reuse prior frames while unrelated chat does not',
    () {
      expect(
        isMediaFollowup('No, that is my girlfriend in the video.'),
        isTrue,
      );
      expect(isMediaFollowup('Look again at the clip.'), isTrue);
      expect(isMediaFollowup('I am hungry'), isFalse);
    },
  );
}
