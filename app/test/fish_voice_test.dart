import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/fish_voice.dart';

void main() {
  test('Fish voice page links can be pasted instead of IDs', () {
    expect(
      FishVoice.voiceIdFromInput(
        'https://fish.audio/app/m/05b451c6e0074aa2bac4a476b0c61ffe/',
      ),
      '05b451c6e0074aa2bac4a476b0c61ffe',
    );
    expect(
      FishVoice.voiceIdFromInput(
        'https://fish.audio/text-to-speech/?modelId=abc123',
      ),
      'abc123',
    );
  });
}
