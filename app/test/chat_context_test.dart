import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/chat_context.dart';
import 'package:local_ai_chat/main.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';

void main() {
  test('voice skips status markers but can speak a reply with an action cue', () {
    expect(isSilentReply('[Stopped]'), isTrue);
    expect(isSilentReply('[whisper] Come closer.'), isFalse);
  });

  test('model input alternates roles after failed or missing chat turns', () {
    LlamaResponseInputItem turn(String role, String text) =>
        LlamaResponseInputItem(role: role, content: [LlamaTextPart(text)]);
    final normalized = alternatingTurns([
      turn('assistant', 'orphaned old answer'),
      turn('user', 'first question'),
      turn('assistant', 'first answer'),
      turn('assistant', 'extra answer'),
      turn('user', 'message before a failed reply'),
      LlamaResponseInputItem(
        role: 'user',
        content: [
          LlamaTextPart('Describe this image.'),
          LlamaImageFilePart(path: 'photo.jpg'),
        ],
      ),
    ]);
    expect(normalized.map((item) => item.role), ['user', 'assistant', 'user']);
    final finalParts = normalized.last.content as List<LlamaContentPart>;
    expect(finalParts.whereType<LlamaImageFilePart>(), hasLength(1));
    expect(finalParts.whereType<LlamaTextPart>(), hasLength(3));
  });

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
    expect(ChatContext.explicitMemory('My name is Alex.'), 'My name is Alex.');
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
