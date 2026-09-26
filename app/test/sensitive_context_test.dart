import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/sensitive_context.dart';

void main() {
  test('does not guess why a sleeping person is undressed', () {
    final reply = sensitiveContextReply('Why is she undressed?', [
      'My sister is asleep beside me.',
    ]);
    expect(reply, contains("can't tell why"));
    expect(reply, contains('privacy'));
  });

  test(
    'responds to the original question without assuming sexual activity',
    () {
      final reply = sensitiveContextReply('What should I do?', [
        'My sister is asleep and undressed.',
      ]);
      expect(reply, contains('Give her privacy'));
      expect(reply, isNot(contains('Stop any sexual contact')));
    },
  );

  test('responds to a consent risk without using the roleplay model', () {
    final reply = sensitiveContextReply('I exposed myself to her.', [
      'My sister is asleep.',
    ]);
    expect(reply, contains("can't consent"));
  });

  test('an unrelated follow-up is not intercepted', () {
    expect(
      sensitiveContextReply('What did you mean by prototype?', [
        'My sister is asleep and undressed.',
      ]),
      isNull,
    );
    expect(sensitiveContextReply('Hello', ['We visited my sister.']), isNull);
  });

  test('an unrelated new media question is not hijacked', () {
    expect(
      sensitiveContextReply('What do you think about these mountains?', [
        'My sister is asleep and undressed.',
      ]),
      isNull,
    );
    expect(
      sensitiveContextReply('Why do stars twinkle?', [
        'My sister is asleep and undressed.',
      ]),
      isNull,
    );
  });
}
