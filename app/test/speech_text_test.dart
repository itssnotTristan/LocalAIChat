import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/speech_text.dart';

void main() {
  test('speech keeps words and pauses without reading markdown or actions', () {
    expect(
      SpeechText.prepare(
        '**Hey!** *(winks, voice dropping to a teasing whisper)* '
        'I am here 😊. [Read more](https://example.com).',
      ),
      'Hey! I am here. Read more.',
    );
    expect(SpeechText.prepare('[whisper] *laughs* Hello!'), 'Hello!');
    expect(
      SpeechText.prepare('That is *really* good.'),
      'That is really good.',
    );
    expect(SpeechText.direction('*laughs* Okay.'), 'chuckle');
  });
}
