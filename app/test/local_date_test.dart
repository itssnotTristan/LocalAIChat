import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/local_date.dart';

void main() {
  test('answers the date from the local clock', () {
    final today = DateTime(2026, 9, 26, 17, 10);
    expect(
      localDateAnswer("What's today's date?", today),
      'Today is Saturday, September 26, 2026.',
    );
    expect(
      localDateAnswer('What day is it today?', today),
      'Today is Saturday, September 26, 2026.',
    );
  });

  test('leaves ordinary questions for the model', () {
    expect(
      localDateAnswer('What happened today?', DateTime(2026, 9, 26)),
      isNull,
    );
  });
}
