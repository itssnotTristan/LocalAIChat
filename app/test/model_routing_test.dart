import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/model_routing.dart';

void main() {
  test('routes factual questions to an instruction model', () {
    expect(asksForGroundedAnswer('Why did she leave?'), isTrue);
    expect(asksForGroundedAnswer('What prototype?'), isTrue);
    expect(asksForGroundedAnswer('What should I do?'), isTrue);
    expect(asksForGroundedAnswer('Describe this picture.'), isTrue);
  });

  test('keeps ordinary character conversation on the selected model', () {
    expect(asksForGroundedAnswer('Tell me a story.'), isFalse);
    expect(asksForGroundedAnswer('Hello, I missed you.'), isFalse);
    expect(asksForGroundedAnswer('What do you want to do tonight?'), isFalse);
  });
}
