import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/uncensored_access.dart';

void main() {
  test('identifies bundled uncensored model names', () {
    expect(isUncensoredModelName('Nymphaea 4B · adult roleplay'), isTrue);
    expect(isUncensoredModelName('Qwen3 VL 4B Abliterated'), isTrue);
    expect(isUncensoredModelName('Ministral 3B · everyday chat'), isFalse);
  });

  test('direct adult requests require the owner preview', () {
    expect(isExplicitAdultTopic('I want erotic roleplay'), isTrue);
    expect(isExplicitAdultTopic('Can I send a nude photo?'), isTrue);
    expect(isExplicitAdultTopic('How do I cook pasta?'), isFalse);
    expect(isExplicitAdultTopic('What is today’s date?'), isFalse);
  });
}
