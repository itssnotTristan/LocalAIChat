import 'package:flutter_test/flutter_test.dart';

import 'package:local_ai_chat/voice_turn_detector.dart';

void main() {
  test('a brief thinking pause does not send a voice turn', () {
    final detector = VoiceTurnDetector(pauseMilliseconds: 1200);
    expect(detector.add(-22, 0), isFalse);
    expect(detector.add(-20, 100), isFalse);
    expect(detector.add(-60, 700), isFalse);
    expect(detector.add(-21, 850), isFalse);
    expect(detector.add(-60, 1900), isFalse);
    expect(detector.add(-60, 2100), isTrue);
  });

  test('carried barge-in audio waits for the rest of the utterance', () {
    final detector = VoiceTurnDetector(pauseMilliseconds: 1000);
    detector.seedSpeech(0);
    expect(detector.add(-19, 300), isFalse);
    expect(detector.add(-61, 1100), isFalse);
    expect(detector.add(-61, 1400), isTrue);
  });

  test('playback bleed alone does not interrupt but sustained speech can', () {
    final detector = VoiceBargeInDetector();
    for (var time = 0; time < 320; time += 80) {
      expect(detector.add(-28, time), isFalse);
    }
    expect(detector.add(-16, 400), isFalse);
    expect(detector.add(-16, 480), isFalse);
    expect(detector.add(-16, 560), isTrue);
  });
}
